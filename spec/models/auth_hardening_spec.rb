# Phase 2 (auth hardening) regression specs — guards that account lockout and idle-session
# timeout stay enabled and correctly configured. Maps: FedRAMP AC-7 (lockout), AC-12 (session timeout).
RSpec.describe 'Auth hardening', type: :model do
  describe 'Devise modules on User' do
    it 'enables account lockout and session timeout' do
      expect(User.devise_modules).to include(:lockable, :timeoutable)
    end
  end

  describe 'account lockout policy (AC-7)' do
    it 'locks after a bounded number of failed attempts' do
      expect(Devise.maximum_attempts).to eq(10)
    end

    it 'locks on failed attempts and auto-unlocks by time (no SMTP dependency)' do
      expect(Devise.lock_strategy).to eq(:failed_attempts)
      expect(Devise.unlock_strategy).to eq(:time)
      expect(Devise.unlock_in).to eq(1.hour)
    end

    it 'has the lockable columns on users' do
      expect(User.column_names).to include('failed_attempts', 'unlock_token', 'locked_at')
    end
  end

  describe 'idle-session timeout (AC-12)' do
    it 'times out inactive sessions' do
      expect(Devise.timeout_in).to eq(30.minutes)
    end
  end
end
