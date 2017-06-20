[![Build Status](https://travis-ci.org/jonatas/export.svg?branch=master)](https://travis-ci.org/jonatas/export)

The idea is implement a simple way to describe what and how should the data be
exported.

Example:

```ruby
users_table = Export.table 'users' do
  replace :full_name, -> { FFaker::Name.name }
  replace :password, 'password'
  replace :email, -> (r) { "#{r.email.split('@').first}@example.com" }
  ignore :created_at, :updated_at
end
```

And then is possible to apply your rules with the tables:

```ruby
dump = Export::TransformData.new('users')
result = dump.process(User.all)
```

And export the tranformed values to a file:

```ruby
File.open('results.json', 'w+') {|f|f.puts result.to_json }
```

Currently you can also specify a dump schema, to fetch a specific scenario of
data:


```ruby
Export.dump 'last 3 monts user' do
  table :users, -> { where: ["created_at > ?",  3.months.ago] }

  all :categories, :products

  ignore :auditable_items

  on_fetch_data {|table, data| puts "Exported #{data.size} from #{table}" }

  on_fetch_error do |table, error, full_trace|
    puts "Ops! something goes wrong importing #{table}", error, full_trace
  end
end
```

Imagine that you also have a table `orders` that depends on `users`. It will
automatically load only the orders related to the current user.

The same will happen with `order_items` that depends of what `orders` are being
exported.

- `all` include all records from n `*tables`
- `table receives a name and allow you specify a scope directly in the model class.


## How to test

We have an example on [examples/rails_test](examples/rails_test) that you can
use:

```bash
cd examples/rails_test
rake db:setup    # Populate with some seeds
rake export:init # Generate the default configuration
```

It will generate an initial suggestion with setting up the configuration:

```
Export.table 'users' do
  replace :full_name, -> { FFaker::Name.name }
  replace :password, 'password'
  replace :email, -> (r) { "#{r.email.split('@').first}@example.com" }
end

Export.table 'addresses'
```

To test all the process:

```
rake export:dump
```

Check the normalized results under `results.json` file.

### TODO

- [ ] Make it load the generated dump file
- [ ] Explore SQL, yml and and other data formats
- [ ] Port `lib/tasks/export.rake` from rails example to the lib
- [ ] Allow use `fake :full_name` syntax

```ruby
Export.table 'users' do
  fake :full_name
  fake :email
end
```
