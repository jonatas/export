# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)
#
require 'ffaker'

User.destroy_all
10_000.times do |i|
  user = User.create(full_name: FFaker::Name.name,
              email: FFaker::Internet.email,
              password: FFaker::Internet.password)

  address = Address.create(street: FFaker::Address.street_name,
                           city: FFaker::Address.city,
                           state: FFaker::AddressUS.state,
                           country: FFaker::Address.country,
                           user: user)
  print '.'
end
