use std::{path::PathBuf, str::FromStr, sync::Arc};

use floem::{
    peniko::Color,
    reactive::{use_context, SignalUpdate},
    style_class,
    taffy::{Display, FlexWrap},
    text::Weight,
    unit::*,
    views::*,
    IntoView,
};
use jiff::{civil::Date, Zoned};
use serde::{Deserialize, Serialize};

use crate::{bg_col2, markdown, AppState, ACC_COL};

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Cv {
    pub personal: Personal,
    pub work: Vec<WorkExperience>,
    pub education: Vec<Education>,
    pub affiliations: Vec<Affiliation>,
    pub awards: Vec<Award>,
    pub certificates: Vec<Certificate>,
    pub publications: Vec<Publication>,
    pub projects: Vec<Project>,
    pub skills: Vec<SkillCategory>,
    pub languages: Vec<Language>,
    pub interests: Option<Vec<String>>,
    pub references: Option<Vec<Reference>>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Personal {
    pub name: String,
    pub email: String,
    pub phone: String,
    pub url: Option<String>,
    pub location: Option<Location>,
    pub profiles: Option<Vec<Profile>>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Location {
    pub city: Option<String>,
    pub region: Option<String>,
    pub postal_code: Option<String>,
    pub country: Option<String>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub network: String,
    pub username: String,
    pub url: Option<String>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct WorkExperience {
    pub organization: String,
    pub position: String,
    pub url: Option<String>,
    pub location: Option<String>,
    pub start_date: String,
    pub end_date: String,
    pub highlights: Option<Vec<String>>,
    pub info_file: Option<PathBuf>,
}
impl IntoView for WorkExperience {
    type V = Stack;

    fn into_view(self) -> Self::V {
        style_class!(Current);
        let start_date = Date::from_str(&self.start_date).unwrap();
        let end_date = Date::from_str(&self.end_date).unwrap();
        let acc_col = ACC_COL.with_alpha_factor(0.85);
        let year = if start_date.year() == end_date.year() {
            start_date.year().to_string()
        } else {
            format!("{} - {}", start_date.year(), end_date.year())
        }
        .style(move |s| {
            s.color(acc_col)
                .font_bold()
                .font_size(15)
                .font_family("SF Pro Text".to_string())
        });

        let role = self.position.style(|s| s.font_size(24).font_bold());

        let company = self.organization.style(|s| {
            s.font_bold()
                .color(Color::LIGHT_GRAY.with_alpha_factor(0.4))
                .font_size(13)
        });

        let role_company = (role, company).h_stack().style(|s| {
            s.justify_between()
                .align_items(Some(floem::taffy::AlignItems::FlexEnd))
                .gap(5)
                .flex_wrap(FlexWrap::Wrap)
        });

        let description = self
            .highlights
            .unwrap_or_default()
            .first()
            .cloned()
            .unwrap_or_default()
            .style(|s| {
                s.font_weight(Weight::LIGHT)
                    .font_size(14)
                    .font_family("SF Pro Text".to_string())
                    .padding_top(10)
            });

        let current = "CURRENT ROLE"
            .style(move |s| {
                s.color(acc_col.with_alpha_factor(0.5))
                    .font_size(10)
                    .apply_if(end_date.year() <= Zoned::now().date().year(), |s| s.hide())
                    .absolute()
                    .inset_top(10)
            })
            .class(Current)
            .animation(move |a| {
                a.view_transition()
                    .duration(500.millis())
                    .keyframe(0, |kf| {
                        kf.style(|s| s.color(acc_col.with_alpha_factor(0.0)))
                    })
            });

        let app_state = use_context::<Arc<AppState>>().unwrap();

        (current, year, role_company, description)
            .v_stack()
            .class(ButtonClass)
            .style(move |s| {
                s.width(350)
                    .min_height(160)
                    .height_full()
                    .gap(10)
                    .padding(15)
                    .padding_top(25)
                    .padding_right(30)
                    .border_radius(8)
                    .background(bg_col2())
                    .box_shadow_color(Color::BLACK.with_alpha_factor(0.3))
                    .box_shadow_spread(3)
                    .box_shadow_blur(3)
                    .box_shadow_v_offset(3)
                    .box_shadow_h_offset(1.5)
                    .margin(5)
                    .class(Current, |s| s.hide())
                    .hover(|s| s.class(Current, |s| s.display(Display::Block)))
            })
            .on_click_stop(move |_| {
                if let Some(info_file) = self.info_file {
                    if info_file.extension().map_or(false, |ext| ext == "md") {
                        let Ok(content) = std::fs::read_to_string(info_file) else {
                            return;
                        };
                        app_state.extra_view.set(Some(Box::new(move || {
                            markdown::markdown(content).into_any()
                        })));
                        app_state.show_extra.set(true);
                    }
                }
            })
    }
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Education {
    pub institution: String,
    pub url: Option<String>,
    pub area: String,
    pub study_type: String,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub location: Option<String>,
    pub honors: Option<Vec<String>>,
    pub courses: Option<Vec<String>>,
    pub highlights: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Affiliation {
    pub organization: String,
    pub position: String,
    pub location: Option<String>,
    pub url: Option<String>,
    pub start_date: String,
    pub end_date: Option<String>,
    pub highlights: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Award {
    pub title: String,
    pub date: String,
    pub issuer: Option<String>,
    pub url: Option<String>,
    pub location: Option<String>,
    pub highlights: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Certificate {
    pub name: String,
    pub date: String,
    pub issuer: Option<String>,
    pub url: Option<String>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Publication {
    pub name: String,
    pub publisher: Option<String>,
    pub release_date: Option<String>,
    pub url: Option<String>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    pub name: String,
    pub url: Option<String>,
    pub affiliation: Option<String>,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub highlights: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct SkillCategory {
    pub category: String,
    pub skills: Vec<String>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Language {
    pub language: String,
    pub fluency: String,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Reference {
    pub name: String,
    pub reference: String,
    pub url: Option<String>,
}
