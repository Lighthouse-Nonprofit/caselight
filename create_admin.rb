# Idempotent dev admin creator. Run inside the app container:
#   docker compose ... run --rm app bundle exec rails runner /app/create_admin.rb
Apartment::Tenant.switch!('cases')
u = User.where(email: 'dev@local.test').first_or_initialize
u.assign_attributes(
  password: 'devpassword',
  password_confirmation: 'devpassword',
  roles: 'admin',
  first_name: 'Dev',
  last_name: 'Admin'
)
u.save!
puts "ADMIN_OK email=#{u.email} id=#{u.id} roles=#{u.roles}"
