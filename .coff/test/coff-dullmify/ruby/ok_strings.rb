# system("ls") in a comment is fine, and so is puts here
def workflow
  note = "system(\"ls\") and puts and File.read appear only in strings"
  doc = <<~TEXT
    Time.now rand exit require 'json'
  TEXT
  words = %w[puts print IO]
  keys = { method: 1, open: 2, p: 3 }
  @open = keys[:open]
  "#{note.size}#{doc.size}#{words.size}#{keys[:send]}#{?p}"
end
