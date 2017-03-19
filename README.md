The idea is implement a simple way to describe what and how should the data be
exported.

Example:

```ruby
export 'users' do
  replace :password, 'password'
  modify :email, (record) -> { strip_email(record.email) }
  modify :full_name, -> { FFaker::namesA.name }
end

export 'billing' do
  mask :credit_card, with: "X"
  modify :address, -> { Faker::Address.street_name }
end

export 'history', limit: 3.months

def strip_email email
 username = email.split('@').first
 "#{username}@example.com"
end
```
