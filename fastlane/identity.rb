# identity.rb
# The bundle ID and team that the app is signed with: Configuration/BetterTG.xcconfig, overridden by the
# Local.xcconfig that ./setup.sh writes for a fork.

module BetterTGIdentity
  CONFIGURATION_DIR = File.expand_path("../Configuration", __dir__)

  def self.settings
    @settings ||= %w[BetterTG.xcconfig Local.xcconfig].each_with_object({}) do |name, settings|
      path = File.join(CONFIGURATION_DIR, name)
      next unless File.exist?(path)

      File.foreach(path) do |line|
        next if line.lstrip.start_with?("//", "#")

        key, value = line.split("=", 2).map(&:strip)
        settings[key] = value if value && key.match?(/\A[A-Z0-9_]+\z/)
      end
    end
  end

  def self.bundle_id
    settings.fetch("BETTERTG_BUNDLE_ID")
  end

  def self.team_id
    settings.fetch("DEVELOPMENT_TEAM")
  end
end
