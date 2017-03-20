The idea is implement a simple way to describe what and how should the data be
exported.

Example:

```ruby
users_table = Export.table 'users' do
  replace :full_name, -> { FFaker::Name.name }
  replace :password, 'password'
  replace :email, -> (r) { "#{r.email.split('@').first}@example.com" }
end
```

And then is possible to apply your rules with the tables:

```ruby
dump = Export::Dump.new(users_table)
result = dump.process(User.all)
```

And export the tranformed values to a file:

```ruby
File.open('results.json', 'w+') {|f|f.puts result.to_json }
```

## How to testo

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

- [ ] Make `Export::Dump` accepts multiple tables
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
