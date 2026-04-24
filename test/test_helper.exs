ExUnit.start()

if File.exists?(".env") do
  Dotenvy.source!(".env")
end
