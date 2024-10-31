
This work sample is from Floem, a cross platform GUI library that I am a core maintainer of.
This is a condensed sample of the `animate.rs` file that contains the majority of the animation engine that I built for use in Floem. 

I've chosen to include this sample because it demonstrates 


```rust
#![deny(missing_docs)]

//! Animations


/// Holds a resolved prop, along with the associated frame id and easing function
#[derive(Clone, Debug)]
pub struct KeyFrameProp {
    // the style prop value. This will either come from an animation frame or it will be pulled from the computed style
    val: Rc<dyn Any>,
    // the frame id
    id: u16,
    /// This easing will be used while animating towards this keyframe. while this prop is the lower one this easing function will not be used.
    easing: Rc<dyn Easing>,
}

/// Holds the style properties for a keyframe as well as the easing function that should be used when animating towards this frame
#[derive(Clone, Debug)]
pub struct KeyFrame {
    #[allow(unused)]
    /// the key frame id. should be less than the maximum key frame number for a given animation
    id: u16,
    style: KeyFrameStyle,
    /// This easing will be used while animating towards this keyframe.
    easing: Rc<dyn Easing>,
}
impl KeyFrame {
    /// Apply a style to this keyframe.
    pub fn style(mut self, style: impl Fn(Style) -> Style) -> Self {
        let style = style(Style::new());
        match &mut self.style {
            cs @ KeyFrameStyle::Computed => *cs = style.into(),
            KeyFrameStyle::Style(s) => s.apply_mut(style),
        };
        self
    }
    ...
}

/// Holds the pair of frame ids that a single prop is animating between
#[derive(Debug, Clone, Copy)]
struct PropFrames {
    // the closeset frame to the target idx that is less than or equal to current
    lower_idx: Option<PropFrameKind>,
    // the closeset frame to the target idx that is greater than current
    upper_idx: Option<PropFrameKind>,
}

/// This cache enables looking up which keyframes contain a given prop, enabling animation of individual props,
/// even if they are sparsely located in the keyframes, with multiple keyframes between each instance of the prop
#[derive(Debug, Clone, Default)]
pub(crate) struct PropCache {
    /// A map of style properties to a list of all frame ids containing that prop
    prop_map: im_rc::HashMap<StylePropRef, SmallVec<[PropFrameKind; 5]>>,
    /// a cached list of all keyframes that use the computed style instead of a separate style
    computed_idxs: SmallVec<[u16; 2]>,
}
impl PropCache {
    /// Find the pair of frames for a given prop at some given target index.
    /// This will find the pair of frames with one lower than the target and one higher than the target.
    /// If it cannot find both, it returns none.
    fn get_prop_frames(&self, prop: StylePropRef, target_idx: u16) -> Option<PropFrames> {
        self.prop_map.get(&prop).map(|frames| {
            match frames.binary_search(&PropFrameKind::Normal(target_idx)) {
                Ok(exact_idx) => {
                    // Exact match found: lower is the exact match, upper is the next frame if it exists
                    let lower = Some(frames[exact_idx]);
                    let upper = frames.get(exact_idx + 1).copied();
                    PropFrames {
                        lower_idx: lower,
                        upper_idx: upper,
                    }
                }
                Err(pos) => {
                    // No exact match found
                    let lower = if pos > 0 {
                        Some(frames[pos - 1]) // Largest smaller frame
                    } else {
                        None
                    };
                    let upper = frames.get(pos).copied(); // Smallest larger frame, if it exists
                    PropFrames {
                        lower_idx: lower,
                        upper_idx: upper,
                    }
                }
            }
        })
    }

    fn insert_prop(&mut self, prop: StylePropRef, idx: PropFrameKind) {
        match self.prop_map.entry(prop) {
            im_rc::hashmap::Entry::Occupied(mut oe) => {
                if let Err(pos) = oe.get().binary_search(&idx) {
                    oe.get_mut().insert(pos, idx)
                }
            }
            im_rc::hashmap::Entry::Vacant(ve) => {
                ve.insert(smallvec![idx]);
            }
        };
    }

    fn insert_computed_prop(&mut self, prop: StylePropRef, idx: PropFrameKind) {
        // computed props are inserted at the start of each call of `animate_into`.
        // Therefore, if the cache does not already contain references to a prop, there will be nothing to animate between and we just don't insert anything.
        if let im_rc::hashmap::Entry::Occupied(mut oe) = self.prop_map.entry(prop) {
            if let Err(pos) = oe.get().binary_search(&idx) {
                oe.get_mut().insert(pos, idx)
            } else {
                unreachable!("this should err because a computed prop shouldn't be inserted more than once. ")
            }
        };
    }

    fn remove_prop(&mut self, prop: StylePropRef, idx: u16) {
        if let im_rc::hashmap::Entry::Occupied(mut oe) = self.prop_map.entry(prop) {
            if let Ok(pos) = oe.get().binary_search(&PropFrameKind::Normal(idx)) {
                oe.get_mut().remove(pos);
            }
        };
    }

    // mark a frame id as for a computed style
    fn insert_computed(&mut self, idx: u16) {
        if let Err(pos) = self.computed_idxs.binary_search(&idx) {
            self.computed_idxs.insert(pos, idx)
        }
    }

    // removed a frame id from being marked as for a computed style
    fn remove_computed(&mut self, idx: u16) {
        if let Ok(pos) = self.computed_idxs.binary_search(&idx) {
            self.computed_idxs.remove(pos);
        }
    }
}

type EffectStateVec = SmallVec<[RwSignal<SmallVec<[(ViewId, StackOffset<Animation>); 1]>>; 1]>;

/// The main animation struct
///
/// Use [Animation::new] or the [Decorators::animation](crate::views::Decorators::animation) method to build an animation.
#[derive(Debug, Clone)]
pub struct Animation {
    pub(crate) state: AnimState,
    pub(crate) effect_states: EffectStateVec,
    pub(crate) auto_reverse: bool,
    pub(crate) delay: Duration,
    pub(crate) duration: Duration,
    pub(crate) repeat_mode: RepeatMode,
    /// How many times the animation has been repeated so far
    pub(crate) repeat_count: usize,
    /// run on remove and run on create should be checked for and respected by any view that dynamically creates sub views
    pub(crate) run_on_remove: bool,
    pub(crate) run_on_create: bool,
    pub(crate) reverse_once: ReverseOnce,
    pub(crate) max_key_frame_num: u16,
    pub(crate) apply_when_finished: bool,
    pub(crate) folded_style: Style,
    pub(crate) key_frames: im_rc::HashMap<u16, KeyFrame>,
    // frames should be added to this if when they are the lower frame, they return not done. check/run them before other frames
    pub(crate) props_in_ext_progress: im_rc::HashMap<StylePropRef, (KeyFrameProp, KeyFrameProp)>,
    pub(crate) cache: PropCache,
    /// This will fire at the start of each cycle of an animation.
    pub(crate) on_start: Trigger,
    /// This tigger will fire at the completion of an animations duration.
    /// Animations are allowed to go on for longer than their duration, until the easing reports finished.
    /// When waiting for the completion of an animation (such as to remove a view), this trigger should be preferred.
    pub(crate) on_visual_complete: Trigger,
    /// This trigger will fire at the total compltetion of an animation when the easing function of all props report 'finished`.
    pub(crate) on_complete: Trigger,
    pub(crate) debug_description: Option<String>,
}
impl Default for Animation {
    fn default() -> Self {
        Animation {
            state: AnimState::Idle,
            effect_states: SmallVec::new(),
            auto_reverse: false,
            delay: Duration::ZERO,
            duration: Duration::from_millis(200),
            repeat_mode: RepeatMode::Times(1),
            repeat_count: 0,
            run_on_remove: false,
            run_on_create: false,
            reverse_once: ReverseOnce::Val(false),
            max_key_frame_num: 100,
            apply_when_finished: false,
            folded_style: Style::new(),
            cache: Default::default(),
            key_frames: im_rc::HashMap::new(),
            props_in_ext_progress: im_rc::HashMap::new(),
            on_start: Trigger::new(),
            on_complete: Trigger::new(),
            on_visual_complete: Trigger::new(),
            debug_description: None,
        }
    }
}


/// # Methods for setting properties on an `Animation`
impl Animation {
    /// Build a KeyFrame
    ///
    /// If there is a matching keyframe id, the style in this keyframe will only override the style values in the new style.
    /// If you want the style to completely override style see [Animation::keyframe_override].
    pub fn keyframe(mut self, frame_id: u16, key_frame: impl Fn(KeyFrame) -> KeyFrame) -> Self {
        let frame = key_frame(KeyFrame::new(frame_id));
        if let KeyFrameStyle::Style(ref style) = frame.style {
            // this frame id now contains a style, so remove this frame id from being marked as computed (if it was).
            self.cache.remove_computed(frame_id);
            for prop in style.style_props() {
                // mark that this frame contains the referenced props
                self.cache
                    .insert_prop(prop, PropFrameKind::Normal(frame_id));
            }
        } else {
            self.cache.insert_computed(frame_id);
        }

        // mutate this keyframe's style to be updated with the new style
        match self.key_frames.entry(frame_id) {
            im_rc::hashmap::Entry::Occupied(mut oe) => {
                let e_frame = oe.get_mut();
                match (&mut e_frame.style, frame.style) {
                    (KeyFrameStyle::Computed, KeyFrameStyle::Computed) => {}
                    (s @ KeyFrameStyle::Computed, KeyFrameStyle::Style(ns)) => {
                        *s = KeyFrameStyle::Style(ns);
                    }
                    (s @ KeyFrameStyle::Style(_), KeyFrameStyle::Computed) => {
                        *s = KeyFrameStyle::Computed;
                    }
                    (KeyFrameStyle::Style(s), KeyFrameStyle::Style(ns)) => {
                        s.apply_mut(ns);
                    }
                };
                e_frame.easing = frame.easing;
            }
            im_rc::hashmap::Entry::Vacant(ve) => {
                ve.insert(frame);
            }
        }
        self
    }

    /// Advance the animation.
    pub fn advance(&mut self) {
        match &mut self.state {
            AnimState::Idle => {
                self.start_mut();
                self.on_start.notify();
            }
            AnimState::PassInProgress {
                started_on,
                mut elapsed,
            } => {
                let now = Instant::now();
                let duration = now - *started_on;
                let og_elapsed = elapsed;
                elapsed = duration;

                let temp_elapsed = if elapsed <= self.delay {
                    // The animation hasn't started yet
                    Duration::ZERO
                } else {
                    elapsed - self.delay
                };

                if temp_elapsed >= self.duration {
                    if self.props_in_ext_progress.is_empty() {
                        self.state = AnimState::PassFinished {
                            elapsed,
                            was_in_ext: false,
                        };
                    } else {
                        self.on_visual_complete.notify();
                        self.state = AnimState::ExtMode {
                            started_on: *started_on,
                            elapsed: og_elapsed,
                        };
                    }
                }
            }
            AnimState::ExtMode {
                started_on,
                mut elapsed,
            } => {
                let now = Instant::now();
                let duration = now - *started_on;
                elapsed = duration;

                if self.props_in_ext_progress.is_empty() {
                    self.state = AnimState::PassFinished {
                        elapsed,
                        was_in_ext: true,
                    };
                }
            }
            AnimState::PassFinished {
                elapsed,
                was_in_ext,
            } => match self.repeat_mode {
                RepeatMode::LoopForever => {
                    self.state = AnimState::PassInProgress {
                        started_on: Instant::now(),
                        elapsed: Duration::ZERO,
                    }
                }
                RepeatMode::Times(times) => {
                    self.repeat_count += 1;
                    if self.repeat_count >= times {
                        self.reverse_once.set(false);
                        self.on_complete.notify();
                        if !*was_in_ext {
                            self.on_visual_complete.notify();
                        }
                        self.state = AnimState::Completed {
                            elapsed: Some(*elapsed),
                        }
                    } else {
                        self.state = AnimState::PassInProgress {
                            started_on: Instant::now(),
                            elapsed: Duration::ZERO,
                        }
                    }
                }
            },
            AnimState::Paused { .. } => {
                debug_assert!(false, "Tried to advance a paused animation")
            }
            AnimState::Stopped => {
                debug_assert!(false, "Tried to advance a stopped animation")
            }
            AnimState::Completed { .. } => {}
        }
    }

    pub(crate) fn transition(&mut self, command: AnimStateCommand) {
        match command {
            AnimStateCommand::Pause => {
                self.state = AnimState::Paused {
                    elapsed: self.elapsed(),
                }
            }
            AnimStateCommand::Resume => {
                if let AnimState::Paused { elapsed } = &self.state {
                    self.state = AnimState::PassInProgress {
                        started_on: Instant::now(),
                        elapsed: elapsed.unwrap_or(Duration::ZERO),
                    }
                }
            }
            AnimStateCommand::Start => {
                self.folded_style.map.clear();
                self.repeat_count = 0;
                self.state = AnimState::PassInProgress {
                    started_on: Instant::now(),
                    elapsed: Duration::ZERO,
                }
            }
            AnimStateCommand::Stop => {
                self.repeat_count = 0;
                self.state = AnimState::Stopped;
            }
        }
    }

    /// Get the lower and upper keyframe ids from the cache for a prop and then resolve those id's into a pair of KeyFrameProps that contain the prop value and easing function
    pub(crate) fn get_current_kf_props(
        &self,
        prop: StylePropRef,
        frame_target: u16,
        computed_style: &Style,
    ) -> Option<(KeyFrameProp, KeyFrameProp)> {
        let PropFrames {
            lower_idx,
            upper_idx,
        } = self.cache.get_prop_frames(prop, frame_target)?;

        let mut upper_computed = false;

        let upper = {
            let upper = upper_idx?;
            let frame = self
                .key_frames
                .get(&upper.inner())
                .expect("If the value is in the cache, it should also be in the key frames");

            let prop = match &frame.style {
                KeyFrameStyle::Computed => {
                    debug_assert!(
                        matches!(upper, PropFrameKind::Computed(_)),
                        "computed frame should have come from matching computed idx"
                    );
                    upper_computed = true;
                    computed_style
                        .map
                        .get(&prop.key)
                        .expect("was in the cache as a computed frame")
                        .clone()
                }
                KeyFrameStyle::Style(s) => s.map.get(&prop.key).expect("same as above").clone(),
            };

            KeyFrameProp {
                id: upper.inner(),
                val: prop,
                easing: frame.easing.clone(),
            }
        };

        let lower = {
            let lower = lower_idx?;
            let frame = self
                .key_frames
                .get(&lower.inner())
                .expect("If the value is in the cache, it should also be in the key frames");

            let prop = match &frame.style {
                KeyFrameStyle::Computed => {
                    debug_assert!(
                        matches!(lower, PropFrameKind::Computed(_)),
                        "computed frame should have come from matching computed idx"
                    );
                    if upper_computed {
                        // both computed. nothing to animate
                        return None;
                    }
                    computed_style
                        .map
                        .get(&prop.key)
                        .expect("was in the cache as a computed frame")
                        .clone()
                }
                KeyFrameStyle::Style(s) => s.map.get(&prop.key).expect("same as above").clone(),
            };

            KeyFrameProp {
                id: lower.inner(),
                val: prop,
                easing: frame.easing.clone(),
            }
        };

        if self.reverse_once.is_rev() {
            Some((upper, lower))
        } else {
            Some((lower, upper))
        }
    }

    /// While advancing, this function can mutably apply it's animated props to a style.
    pub fn animate_into(&mut self, computed_style: &mut Style) {
        // TODO: OPTIMIZE. I've tried to make this efficient, but it would be good to work this over for eficiency because it is called on every frame during an animation.
        // Some work is repeated and could be improved.

        let computed_idxs = self.cache.computed_idxs.clone();
        for computed_idx in &computed_idxs {
            // we add all of the props from the computed style to the cache becaues the computed style could change inbetween every frame.
            for prop in computed_style.style_props() {
                self.cache
                    .insert_computed_prop(prop, PropFrameKind::Computed(*computed_idx));
            }
        }
        let local_percents: Vec<_> = self
            .props_in_ext_progress
            .iter()
            .map(|(p, (l, u))| (*p, self.get_local_percent(l.id, u.id)))
            .collect();

        self.props_in_ext_progress.retain(|p, (_l, u)| {
            let local_percent = local_percents
                .iter()
                .find(|&&(prop, _)| prop == *p)
                .map(|&(_, percent)| percent)
                .unwrap_or_default();
            !u.easing.finished(local_percent)
        });
        for (ext_prop, (l, u)) in &self.props_in_ext_progress {
            let local_percent = local_percents
                .iter()
                .find(|&&(prop, _)| prop == *ext_prop)
                .map(|&(_, percent)| percent)
                .unwrap_or_default();

            let eased_time = u.easing.eval(local_percent);
            if let Some(interpolated) =
                (ext_prop.info().interpolate)(&*l.val.clone(), &*u.val.clone(), eased_time)
            {
                self.folded_style.map.insert(ext_prop.key, interpolated);
            }
        }

        let percent = self.total_time_percent();
        let frame_target = (self.max_key_frame_num as f64 * percent).round() as u16;

        let props = self.cache.prop_map.keys();

        for prop in props {
            if self.props_in_ext_progress.contains_key(prop) {
                continue;
            }
            let Some((lower, upper)) =
                self.get_current_kf_props(*prop, frame_target, computed_style)
            else {
                continue;
            };
            let local_percent = self.get_local_percent(lower.id, upper.id);
            let easing = upper.easing.clone();
            // TODO: Find a better way to find when an animation should enter ext mode rather than just starting to check after 97%.
            // this could miss getting a prop into ext mode
            if (local_percent > 0.97) && !easing.finished(local_percent) {
                self.props_in_ext_progress
                    .insert(*prop, (lower.clone(), upper.clone()));
            } else {
                self.props_in_ext_progress.remove(prop);
            }
            let eased_time = easing.eval(local_percent);
            if let Some(interpolated) =
                (prop.info().interpolate)(&*lower.val.clone(), &*upper.val.clone(), eased_time)
            {
                self.folded_style.map.insert(prop.key, interpolated);
            }
        }

        computed_style.apply_mut(self.folded_style.clone());

        // we remove all of the props in the computed style from the cache becaues the computed style could change inbetween every frame.
        for computed_idx in computed_idxs {
            for prop in computed_style.style_props() {
                self.cache.remove_prop(prop, computed_idx);
            }
        }
    }
}
```
