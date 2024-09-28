mod app_config;
mod cv;
mod markdown;

use std::{fs::File, sync::Arc};

use app_config::launch_with_track;
use cv::Cv;
use dyn_clone::DynClone;
use floem::{
    peniko::Color,
    reactive::{provide_context, RwSignal, SignalGet, SignalUpdate},
    responsive::ScreenSize,
    style::{InsetRight, ScaleX, ScaleY, StylePropValue, Transition},
    unit::{DurationUnitExt, UnitExt},
    views::{
        scroll::{ScrollClass, ScrollCustomStyle, ScrollExt},
        *,
    },
    AnyView, IntoView,
};
use lipsum::lipsum;
use lucide_floem::{Icon as I, LucideClass, StrokeWidth};

fn main() {
    launch_with_track(app_view);
}

const BG_COL: Color = Color::rgb8(31, 41, 83);
const ACC_COL: Color = Color::rgb8(7, 218, 108);
fn bg_col2() -> Color {
    BG_COL.interpolate(&Color::BLACK, 0.18).unwrap()
}

struct AppState {
    extra_view: RwSignal<Option<Box<dyn ViewCloneFn>>>,
    show_extra: RwSignal<bool>,
}
impl Default for AppState {
    fn default() -> Self {
        Self {
            extra_view: RwSignal::new(None),
            show_extra: RwSignal::new(false),
        }
    }
}

pub fn app_view() -> impl IntoView {
    let app_state = Arc::new(AppState::default());
    provide_context(app_state.clone());

    h_stack((
        main_window(app_state.clone()),
        content_slide_over(app_state),
    ))
    .style(|s| {
        s.size_full()
            .background(BG_COL)
            .color(Color::WHITE_SMOKE.with_alpha_factor(0.9))
            .class(LucideClass, |s| {
                s.size(50, 50)
                    .set(StrokeWidth, 1.2)
                    .class(SvgClass, |s| s.color(Color::WHITE_SMOKE))
            })
            .class(ButtonClass, |s| {
                s.transition(ScaleX, Transition::spring(300.millis()))
                    .transition(ScaleY, Transition::spring(300.millis()))
                    // .scale_x(100.pct())
                    .hover(|s| s.scale(104.pct()))
                // .focus(|s| s.scale(110.pct()))
            })
            .class(TooltipContainerClass, |s| s.set(Delay, 400.millis()))
            .class(TooltipClass, |s| {
                s.color(Color::WHITE_SMOKE.with_alpha_factor(0.8))
                    .font_bold()
                    .border_radius(5)
                    .box_shadow_color(Color::BLACK.with_alpha_factor(0.3))
                    .box_shadow_spread(3)
                    .box_shadow_blur(3)
                    .box_shadow_v_offset(3)
                    .box_shadow_h_offset(1.5)
                    .background(bg_col2().interpolate(&Color::WHITE, 0.08).unwrap())
                    .padding(10)
            })
            .class(LabelClass, |s| {
                s.apply_custom(
                    LabelCustomStyle::new().selection_color(
                        bg_col2()
                            .interpolate(&Color::WHITE, 0.12)
                            .unwrap()
                            .with_alpha_factor(0.6),
                    ),
                )
            })
            .class(ScrollClass, |s| {
                s.apply_custom(ScrollCustomStyle::new().handle_thickness(8))
            })
    })
}

dyn_clone::clone_trait_object!(ViewCloneFn);

trait ViewCloneFn: DynClone {
    fn get(&self) -> AnyView;
}
impl<F: DynClone> ViewCloneFn for F
where
    F: Fn() -> AnyView,
{
    fn get(&self) -> AnyView {
        (self.clone())()
    }
}

fn content_slide_over(app_state: Arc<AppState>) -> impl IntoView {
    let extra_view = app_state.extra_view;
    let show_extra = app_state.show_extra;

    let content = dyn_container(
        move || {
            extra_view.try_update(|val| {
                val.take()
                    .map(|v| v.get())
                    .unwrap_or_else(|| empty().into_any())
                    .style(|s| s.min_size(0, 0))
            })
        },
        |c| c.unwrap(),
    );

    let content_container = content.container().style(|s| {
        s.min_size(0, 0)
            .padding_bottom(50)
            .max_width(600)
            .responsive(ScreenSize::MD | ScreenSize::SM | ScreenSize::XS, |s| {
                s.max_width(400).line_height(1.5)
            })
    });

    let content_scroll = content_container
        .scroll()
        .style(|s| {
            s.size_full()
                .font_size(18)
                .line_height(2.)
                .min_size(0, 0)
                .justify_center()
        })
        .scroll_style(|s| s.handle_background(Color::WHITE.with_alpha_factor(0.3)));

    let close_icon = button(I::CircleX.style(|s| s.size(30, 30)))
        .style(|s| {
            s.absolute()
                .inset_left(20)
                .inset_top(20)
                .padding(5)
                .border_radius(10)
                .background(BG_COL)
                .transition_background(Transition::spring(300.millis()))
                .hover(|s| {
                    s.box_shadow_color(Color::BLACK.with_alpha_factor(0.3))
                        .box_shadow_spread(3)
                        .box_shadow_blur(3)
                        .box_shadow_v_offset(3)
                        .box_shadow_h_offset(1.5)
                        .background(bg_col2())
                })
        })
        .action(move || show_extra.set(false));

    let slide_over = (close_icon, content_scroll).h_stack().style(move |s| {
        s.absolute()
            .padding_top(50)
            .padding_left(20)
            .padding_right(10)
            .inset_top(0)
            .inset_right_pct(0.)
            .size_full()
            .background(BG_COL)
            .transition(InsetRight, Transition::ease_in_out(400.millis()))
            .apply_if(!show_extra, |s| s.inset_right_pct(-100.))
    });
    slide_over
}

fn main_window(app_state: Arc<AppState>) -> impl IntoView {
    let file = File::open("content.yml").unwrap();
    let cv: Cv = serde_yaml::from_reader(file).unwrap();

    let jobs = cv.work;

    let experience_cards = jobs
        .h_stack()
        .style(|s| s.gap(15).margin_bottom(8 * 2).padding_vert(15))
        .scroll()
        .scroll_style(|s| s.overflow_clip(false).handle_background(ACC_COL))
        .style(|s| {
            s.min_size(0, 0)
                .gap(15)
                .font_family("SF Pro Display".to_string())
        });

    let content_height = RwSignal::new(0.);
    let content = v_stack((
        "Skills & Experience".to_uppercase(),
        "My Resume"
            .to_uppercase()
            .style(|s| s.font_size(48).font_bold()),
        "I've done some pretty cool stuff".style(|s| {
            s.padding_bottom(15)
                .color(Color::WHITE_SMOKE.with_alpha_factor(0.5))
        }),
        experience_cards,
    ))
    .style(|s| s.gap(15).min_size(0, 0))
    .on_resize(move |r| content_height.set(r.height()));

    let show = app_state.show_extra;
    let extra_view = app_state.extra_view;

    let microcontrollers_area = skill_area(I::Microchip)
        .tooltip(|| "Microcontrollers")
        .on_click_stop(move |_| {
            extra_view.set(Some(Box::new(move || lipsum(500).into_any())));
            show.set(true)
        });
    let gui_area = skill_area(I::AppWindow).tooltip(|| "GUI Library");

    let icons = (microcontrollers_area, gui_area).v_stack().style(move |s| {
        s.height(content_height.get())
            .width(300)
            .items_center()
            .justify_content(Some(floem::taffy::AlignContent::SpaceAround))
    });

    let grab_bar = drag_window_area(empty()).style(|s| {
        s.absolute()
            .inset_top(0)
            .inset_right(0)
            .width_full()
            .height(50)
    });

    let full_page = (grab_bar, icons, content).h_stack();
    // let id = full_page.id();
    // id.inspect();

    full_page.style(|s| s.size_full().items_center().padding_left(15))
}

pub fn skill_area(icon: I) -> impl IntoView {
    icon.style(|s| {
        s.padding(10)
            .background(BG_COL)
            .transition_background(Transition::spring(300.millis()))
            .hover(|s| {
                s.box_shadow_color(Color::BLACK.with_alpha_factor(0.3))
                    .box_shadow_spread(3)
                    .box_shadow_blur(3)
                    .box_shadow_v_offset(3)
                    .box_shadow_h_offset(1.5)
                    .background(bg_col2())
            })
    })
    .class(ButtonClass)
}
