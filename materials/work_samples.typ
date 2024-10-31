
#set raw(theme: "/gruvbox-dark-soft.tmTheme")
#show raw: it => {
  set page(margin: 0pt)
  block(
  inset: 20pt,
  radius: 5pt,
  width: 100%,
  fill: rgb("#32302f"),
    text(size: 8pt, fill: rgb("#a2aabc"), it)
  )
};
#set text(font: "SF Pro Display")

== Leviathan: I2C Daisy Chain

#include "/materials/leviathan.typ"
