struct QuickText { var text: String }
let quickText = QuickText(text: "Hello")
let str = "Edit \(quickText.text.isEmpty ? "Unnamed Text" : quickText.text)"
print(str)
