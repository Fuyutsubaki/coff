def workflow
  ask("q")
rescue Exception
  "swallowed"
end
