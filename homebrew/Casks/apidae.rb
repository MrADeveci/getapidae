cask "apidae" do
  version "0.3.0"
  sha256 :no_check

  url "https://github.com/MrADeveci/getapidae/releases/download/v#{version}/Apidae.dmg"
  name "Apidae"
  desc "Cover your Mac screen so AI agents and background tasks can keep running"
  homepage "https://getapidae.com"

  depends_on macos: ">= :sonoma"

  app "Apidae.app"

  zap trash: [
    "~/Library/Preferences/app.getapidae.mac.plist",
  ]
end
