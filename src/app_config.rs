use floem::views::Decorators;
use floem::window::WindowButtons;
use floem::{
    event::{Event, EventListener},
    kurbo::{Point, Size},
    reactive::{create_updater, RwSignal, SignalGet, SignalUpdate, SignalWith},
    window::WindowConfig,
    Application, IntoView,
};
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Serialize, Clone, Copy, PartialEq, Eq, Debug)]
pub enum AppTheme {
    FollowSystem,
    DarkMode,
    LightMode,
}

#[derive(Deserialize, Serialize, Clone, Copy, PartialEq, Eq, Debug)]
pub struct AppThemeState {
    pub system: floem::window::Theme,
    pub theme: AppTheme,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct AppConfig {
    pub position: Point,
    pub size: Size,
    pub app_theme: AppThemeState,
    pub sliders_on: bool,
    // pub window_scale: WindowScale,
}

impl std::default::Default for AppConfig {
    fn default() -> Self {
        Self {
            position: Point { x: 500.0, y: 500.0 },
            size: Size {
                width: 350.0,
                height: 650.0,
            },
            app_theme: AppThemeState {
                system: floem::window::Theme::Dark,
                theme: AppTheme::FollowSystem,
            },
            sliders_on: true,
            // window_scale: WindowScale(1.),
        }
    }
}

pub fn launch_with_track<V: IntoView + 'static>(app_view: impl FnOnce() -> V + 'static) {
    let config: AppConfig = confy::load("my_app", "floem-defaults").unwrap_or_default();

    let app = Application::new();

    // modifying this will rewrite app config to disk
    let app_config = RwSignal::new(config);

    create_updater(
        move || app_config.get(),
        |config| {
            let _ = confy::store("my_app", "floem-defaults", config);
        },
    );

    let window_config = WindowConfig::default()
        .size(app_config.with(|ac| ac.size))
        .font_embolden(0.1)
        .apply_default_theme(false)
        .show_titlebar(false)
        // .enabled_buttons(WindowButtons::empty())
        .with_mac_os_config(|mc| mc.full_size_content_view(true).hide_titlebar_buttons(true))
        .position(app_config.with(|ac| ac.position));

    app.window(
        move |_| {
            app_view()
                .on_event_stop(EventListener::WindowMoved, move |event| {
                    if let Event::WindowMoved(position) = event {
                        app_config.update(|val| {
                            val.position = *position;
                        })
                    }
                })
                .on_event_stop(EventListener::WindowResized, move |event| {
                    if let Event::WindowResized(size) = event {
                        app_config.update(|val| {
                            val.size = *size;
                        })
                    }
                })
        },
        Some(window_config),
    )
    .run();
}
