
#let letter(
  sender-name: none,
  sender-address: none,
  sender-city: none,
  sender-email: none,
  sender-phone: none,
  date: none,
  recipient-name: none,
  recipient-title: none,
  recipient-company: none,
  recipient-address: none,
  recipient-city: none,
  body,
) = {
  // Set document styling
  set document(author: sender-name, title: "Cover Letter")
  set text(font: "New Computer Modern", size: 11pt)
  set page(
    margin: (left: 1in, right: 1in, top: 1in, bottom: 1in),
  )
  
  // Sender info block
  align(left)[
    #sender-name \
    #sender-address \
    #sender-city \
    #sender-email \
    #sender-phone
  ]
  
  v(24pt)
  
  // Date
  align(left)[#date]
  
  v(24pt)
  
  // Recipient block
  align(left)[
    #recipient-name \
    #recipient-title \
    #recipient-company \
    #recipient-address \
    #recipient-city
  ]
  
  v(24pt)
  
  // Salutation
  if recipient-name != none {
    [Dear #recipient-name,]
  } else {
    [Dear Hiring Manager,]
  }
  
  // Letter body
  par(justify: true)[#body]
  
  v(24pt)
  
  // Closing
  align(left)[
    Sincerely, \
    #v(48pt) \
    #sender-name
  ]
}
