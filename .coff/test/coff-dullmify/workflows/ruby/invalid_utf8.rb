def workflow
  Dullmify.arguments
  ("不正:".b + "\xFF".b).force_encoding(Encoding::UTF_8)
end
