

This work sample is from the firmware of a product that I built for Bently Nevada. 
It is given the name of Leviathan and is a dual-channel, arbitrary waveform generator that interafaces over USB with a host software.
The custom PCB and assembly was designed by a hardware engineer and I was tasked with building the firmware and the host software.

The host software connects to one or more device chains over USB, where each chain is a daisy chain of Leviathan devices.

#align(center, grid(align: horizon, columns: 2, image("leviathan/device.png", width: 30%), image("leviathan/mock-leviathan.png")))

This sample, specifically, is the code that I wrote that handles the daisy chain connection over I2C with other Leviathan devices. 
```rust
use core::{future::poll_fn, sync::atomic::Ordering};

use common::protocol::Protocol;
use embassy_executor::Spawner;
use embassy_futures::select;
use embassy_time::{Duration, Ticker, with_timeout};
use futures::FutureExt as _;
use hal::{
    exti::ExtiInput,
    gpio::Output,
    i2c::{I2c, mode::MultiMaster},
    mode::Async,
};

use crate::{
    devices::lev_slave::{self, I2CMessage, SIZE_MESSAGE_SIZE},
    extensions::*,
    statics::*,
    tasks::host_command::handle_host_command,
};

#[embassy_executor::task]
/// A task that checks if the downstream device is connected.
///
/// Every 300ms, it checks if the downstream device is connected. If it is, it
/// sends a request for device info. If it is not,
/// it sends a lost child command upstream to the host (necessary).
///
/// # Theory and Importance of sending lost child command
/// When a downstream device disconnects, for any reason, the host needs to
/// know. Because the downstream device is not connected, it cannot send a
/// message to the host. The upstream device, however, can send a message to the
/// host. This message is the lost child command.
///
/// This device does not store the serial number of any downstream devices
/// though. So, when the host receives the lost child command, it will
/// recursively look up and remove the serial number of the downstream device
/// using the serial number of this device. It does this using a HashMap of
/// serial numbers (parent) to serial numbers (child) and removes them from the
/// UI.
pub async fn check_downstream_connected() {
    let mut ticker = Ticker::every(Duration::from_millis(300));
    let mut prev_connected = false;
    loop {
        ticker.next().await;
        let Ok(mut locked) = DOWN_STREAM_LEV.try_lock() else {
            continue;
        };
        defmt::trace!("Checking downstream connection");
        if let Some(lev) = locked.as_mut() {
            match with_timeout(Duration::from_millis(30), lev.check_connected()).await {
                Ok(Ok(true)) => {
                    if !prev_connected {
                        defmt::info!("Downstream connected");
                        let proto = Protocol::request_device_infos(u32::random().await.unwrap());
                        INTER_COM_DOWN_CH.send(proto).await;
                        prev_connected = true;
                    }
                },
                _ => {
                    if prev_connected {
                        defmt::info!("Downstream disconnected");
                        let command =
                            Protocol::lost_child(get_serial_number(), u32::random().await.unwrap());
                        if USB_CONNECTED.load(Ordering::Acquire) {
                            USB_PROTO_CHANNEL.send(command).await;
                        } else {
                            INTER_COM_UP_CH.send(command).await;
                        }
                        prev_connected = false;
                    }
                },
            }
        }
    }
}

#[embassy_executor::task]
/// A task that reads `Protocol` messages from the downstream device.
///
/// Waits for a falling edge on the EXTI line on the frame in pin connected to
/// the downstream device's frame out pin.
///
/// When a message is received from a downstream device, it only needs to be
/// sent upstream (USB or I2C).
pub async fn read_from_downstream(mut frame_in: ExtiInput<'static>) {
    loop {
        frame_in.wait_for_falling_edge().await;
        defmt::info!("Trying to read from downstream");

        let Ok(mut locked) = DOWN_STREAM_LEV.try_lock() else {
            continue;
        };
        let result =
            with_timeout(Duration::from_millis(300), locked.as_mut().unwrap().read()).await;
        if let Ok(Ok(Some(mut command))) = result {
            defmt::debug!("Received command from downstream: {:#?}", command);
            if command.is_device_info_no_parent() {
                command.set_parent(get_serial_number());
            }
            if USB_CONNECTED.load(core::sync::atomic::Ordering::Acquire) {
                USB_PROTO_CHANNEL.send(command).await;
            } else {
                INTER_COM_UP_CH.send(command).await;
            }
        } else {
            defmt::warn!("{:#?}", result);
        }
    }
}

#[embassy_executor::task]
/// A task that sends `Protocol` messages to the downstream device.
///
/// If no downstream device is connected, the message will be dropped.
pub async fn send_to_downstream() {
    loop {
        let command = INTER_COM_DOWN_CH.receive().await;
        defmt::debug!("Sending command to downstream: {:#?}", command);
        DOWN_STREAM_LEV
            .lock()
            .await
            .as_mut()
            .unwrap()
            .write(command)
            .await
            .ok_or_warn();
    }
}

enum NextMessageToReceive {
    Size,
    Data(u16),
}
#[allow(clippy::large_enum_variant)]
enum NextMessageToSend {
    Size,
    Data(heapless::Vec<u8, 250>),
}

#[embassy_executor::task]
pub async fn listen_to_upstream(
    mut slave: I2c<'static, Async, MultiMaster>, spawner: Spawner, mut frame_out: Output<'static>,
) {
    let mut next_message_to_receive = NextMessageToReceive::Size;
    let mut next_message_to_send = NextMessageToSend::Size;
    let mut ready = true;
    let mut ticker = Ticker::every(Duration::from_millis(300));
    let mut count_no_read = 0;
    defmt::info!("Listening for I2C commands");
    loop {
        defmt::trace!("Listen for new I2C command");
        let ready_to_rec = poll_fn(|cx| {
            if count_no_read > 10 {
                return core::task::Poll::Pending;
            }
            if ticker.next().poll_unpin(cx).is_ready() && !INTER_COM_UP_CH.is_empty() {
                count_no_read += 1;
                return core::task::Poll::Ready(());
            };
            if ready {
                match INTER_COM_UP_CH.poll_ready_to_receive(cx) {
                    core::task::Poll::Ready(_) => {
                        ready = false;
                        core::task::Poll::Ready(())
                    },
                    core::task::Poll::Pending => core::task::Poll::Pending,
                }
            } else {
                core::task::Poll::Pending
            }
        });
        match select::select(slave.listen(), ready_to_rec).await {
            select::Either::First(Ok(hal::i2c::SlaveCommand {
                kind,
                address: hal::i2c::Address::SevenBit(_),
            })) => {
                ready = true;
                count_no_read = 0;
                match kind {
                    hal::i2c::SlaveCommandKind::Write => {
                        send_to_master(&mut slave, &mut next_message_to_send).await
                    },
                    hal::i2c::SlaveCommandKind::Read => {
                        receive_from_master(&mut slave, &mut next_message_to_receive, spawner).await
                    },
                }
            },
            select::Either::Second(_) => {
                defmt::debug!("toggling frame pin");
                frame_out.set_low();
                frame_out.set_high();
            },
            _ => continue,
        }
    }
}

async fn receive_from_master(
    slave: &mut I2c<'static, Async, MultiMaster>,
    next_message_to_receive: &mut NextMessageToReceive, spawner: Spawner,
) {
    let buffer = &mut [0u8; 250];
    let size = match next_message_to_receive {
        NextMessageToReceive::Size => lev_slave::SIZE_MESSAGE_SIZE,
        NextMessageToReceive::Data(size) => {
            defmt::trace!("preparign to receiving {} data bytes from the master", size);
            *size as usize
        },
    };
    let Some(response_size) = slave
        .respond_to_write(&mut buffer[..size])
        .await
        .ok_or_warn()
    else {
        defmt::warn!("Failed to receive from master");
        return;
    };

    if response_size == lev_slave::SIZE_MESSAGE_SIZE
        && buffer[..response_size]
            .iter()
            .all(|val| *val == lev_slave::ACK_BYTE)
    {
        defmt::trace!("Received ACK from master");
        return;
    }

    if response_size != size {
        *next_message_to_receive = NextMessageToReceive::Size;
        defmt::warn!(
            "Received response from master with unexpected length: {}",
            response_size
        );
        return;
    }

    defmt::trace!(
        "Received response from master. total len: {}",
        response_size
    );

    let Some(message) = postcard::from_bytes::<I2CMessage>(buffer).ok_or_warn() else {
        defmt::warn!("Failed to parse message from master");
        return;
    };

    let command = match message {
        I2CMessage::Size(size) => {
            *next_message_to_receive = NextMessageToReceive::Data(size);
            defmt::trace!("setting size of data to receive to {}", size);
            return;
        },
        I2CMessage::Message(proto) => {
            *next_message_to_receive = NextMessageToReceive::Size;
            proto
        },
    };
    defmt::info!("InterCom Receive: Got message from master");
    defmt::debug!("Message: {:#?}", command);

    let is_broadcast = command.header.is_broadcast;
    if is_broadcast {
        // we forward it to the slave and handle it ourselves
        INTER_COM_DOWN_CH.send(command.clone()).await;
        // defmt::unwrap!(spawner.spawn(handle_host_command(command, spawner)));
        spawner.spawn(handle_host_command(command, spawner)).ok();
    } else if command.header.receiver_serial_num == get_serial_number() {
        // if the serial number matches ours, we handle the command
        // defmt::unwrap!(spawner.spawn(handle_host_command(command, spawner)));
        spawner
            .spawn(handle_host_command(command, spawner))
            .ok_or_warn();
    } else {
        INTER_COM_DOWN_CH.send(command.clone()).await;
    }
}

async fn send_to_master(
    slave: &mut I2c<'static, Async, MultiMaster>, next_message_to_send: &mut NextMessageToSend,
) {
    // if we have a command to pass up we send it here
    match next_message_to_send {
        NextMessageToSend::Size => {
            if let Ok(command) = INTER_COM_UP_CH.try_receive() {
                let to_send = postcard::to_vec::<_, 250>(&command).unwrap();
                let len = to_send.len() as u16;
                let message = I2CMessage::Size(len);
                let data =
                    defmt::unwrap!(postcard::to_vec::<I2CMessage, SIZE_MESSAGE_SIZE>(&message));
                slave.respond_to_read(&data).await.ok_or_warn();
                *next_message_to_send = NextMessageToSend::Data(to_send);
            } else {
                defmt::warn!("Master did a read when there was no data to send");
                slave.respond_to_read(&[0; SIZE_MESSAGE_SIZE]).await.ok();
            }
        },
        NextMessageToSend::Data(data) => {
            slave.respond_to_read(data).await.ok_or_warn();
            *next_message_to_send = NextMessageToSend::Size;
        },
    }
}

```
