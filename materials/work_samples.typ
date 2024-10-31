
#set raw(theme: "../gruvbox-dark-soft.tmTheme")
#show raw: it => {
  // set page(margin: 0pt)
  block(
  inset: 20pt,
  radius: 5pt,
  width: 100%,
  fill: rgb("#32302f"),
    text(size: 8pt, fill: rgb("#a2aabc"), it)
  )
};

#show heading.where(level: 2): it => {
  // set align(center)
  // set text(rgb("#E0412E"))
  pad(bottom: 1em, it)
}

#set text(font: "SF Pro Display")

== Leviathan: I2C Daisy Chain

#pad(left: 1.5em, [
  #include "/materials/leviathan.typ"
])


== Embassy I2C Slave



== Floem animation engine

#pad(left: 1.5em, [
  #include "/materials/floem-animation.typ"
  
])
