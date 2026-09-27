def workflow
  ask("q")
rescue Object
  "swallowed"
end
