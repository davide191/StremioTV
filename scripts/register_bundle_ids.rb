#!/usr/bin/env ruby
# Enregistre les deux Bundle IDs sur le compte via l'App Store Connect API
# (clé .p8) — idempotent. Contrairement à la création d'une *fiche d'app*, la
# création d'un Bundle ID est supportée par la clé API.
#
# Usage :
#   ASC_KEY_ID=... ASC_ISSUER_ID=... P8_PATH=~/Downloads/AuthKey_XXXX.p8 \
#     bundle exec ruby scripts/register_bundle_ids.rb
require "spaceship"

token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("ASC_KEY_ID"),
  issuer_id: ENV.fetch("ASC_ISSUER_ID"),
  key: File.read(File.expand_path(ENV.fetch("P8_PATH")))
)
Spaceship::ConnectAPI.token = token

targets = [
  ["com.nicolasbataille.stremiotv",    "StremioTV iOS"],
  ["com.nicolasbataille.stremiotv.tv", "StremioTV tvOS"],
]

existing = Spaceship::ConnectAPI::BundleId.all.map(&:identifier)

targets.each do |identifier, name|
  if existing.include?(identifier)
    puts "OK  déjà enregistré : #{identifier}"
  else
    Spaceship::ConnectAPI::BundleId.create(
      name: name,
      identifier: identifier,
      platform: Spaceship::ConnectAPI::BundleIdPlatform::IOS
    )
    puts "NEW créé : #{identifier} (#{name})"
  end
end
