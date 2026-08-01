describe 'Client' do
  let(:admin) { create(:user, roles: 'admin') }
  let(:user) { create(:user) }

  feature 'List' do
    let!(:client){create(:client, users: [user])}
    let!(:other_client) {create(:client)}
    let!(:domain) { create(:domain, name: "1A") }

    before do
      login_as(user)
      visit clients_path
    end

    scenario 'new link' do
      expect(page).to have_link(I18n.t('clients.index.add_new_client')) # 'Add New Individual' (SLO4HOME)
    end

    scenario 'name' do
      expect(page).to have_content(client.name)
    end

    # (UX rung 2: the index edit/delete buttons are gone — the card is the click target and
    # edit/delete live on the show page; the show-page delete scenario below still covers it.)
    scenario 'no other name' do
      expect(page).not_to have_content(other_client.name)
    end

    scenario 'admin' do
      login_as(admin)
      visit clients_path
      expect(page).to have_content(client.name)
      expect(page).to have_content(other_client.name)
    end
  end

  feature 'Reports' do
    before do
      login_as(admin)
      # Investor UX round (2026-07): the charts live on the Reports landing page now.
      visit reports_path
    end
    scenario 'Domain Score Statistic and Enrollment Statistic', js: true do
      expect(page).to have_css("#cis-domain-score[data-title='#{I18n.t('reports.index.csi_domain_scores')}']")
      expect(page).to have_css("#cis-domain-score[data-yaxis-title='Domain Scores']")
      # Reports batch R8: the flavor-correct enrollments chart replaced the EC/FC/KC case chart
      expect(page).to have_css("#enrollment-statistic[data-title='#{I18n.t('reports.index.enrollment_statistics')}']")
      expect(page).to have_css("#enrollment-statistic[data-yaxis-title='#{I18n.t('reports.index.enrollment_amount')}']")
    end
  end

  feature 'Show' do
    let!(:client){ create(:client, users: [user], state: 'accepted') }
    let!(:other_client){create(:client)}
    before do
      login_as(user)
      visit client_path(client)
    end
    scenario 'information' do
      expect(page).to have_content(client.name)
      expect(page).to have_content(client.gender.capitalize)
      expect(page).to have_content(client.date_of_birth.strftime('%B %d, %Y'))
    end

    scenario 'tasks link' do
      expect(page).to have_link('Tasks')
    end

    scenario 'assesstments link' do
      expect(page).to have_link('Assessments')
    end

    scenario 'case notes link' do
      expect(page).to have_link('Case Note')
    end

    scenario 'edit link' do
      expect(page).to have_link(nil)
    end

    scenario 'delete link' do
      expect(page).to have_css("a[href='#{client_path(client)}'][data-method='delete']")
    end
  end

  feature 'New' do
    let!(:province) { create(:province) }
    let!(:client)   { create(:client, given_name: 'Branderson', family_name: 'Anderson', local_given_name: 'Vin',
                             local_family_name: 'Kell', date_of_birth: '2017-05-01', birth_province: province,
                             province: province, village: 'Sabay', commune: 'Vealvong') }
    before do
      login_as(user)
      visit new_client_path
    end
    scenario 'valid', js: true do
      fill_in 'Given Name', with: 'Kema'
      find(".client_users select option[value='#{user.id}']", visible: false).select_option
      click_button 'Save'
      wait_for_ajax
      expect(page).to have_content('Kema')
    end

    scenario 'invalid as missing case workers', js: true do
      fill_in 'Given Name', with: FFaker::Name.name
      click_button 'Save'
      wait_for_ajax
      expect(page).to have_content("can't be blank")
    end

    # BS5-Q3: Client.filter is EXACT-equality since Phase 4 Tier 4 (deterministic
    # encryption dropped the 75%-prefix fuzzy match), so only exact name matches
    # trigger the duplicate warning now — fill the fixture's exact names.
    scenario 'warning', js: true do
      fill_in 'Given Name', with: 'Branderson'
      fill_in 'Family Name', with: 'Anderson'
      fill_in 'Given Name (native)', with: 'Vin'
      fill_in 'Family Name (native)', with: 'Kell'
      fill_in 'Date of Birth', with: '2017-05-01'
      find(".client_users select option[value='#{user.id}']", visible: false).select_option

      # no .client_province select anymore — the "State" select is pilot-hidden (polish)
      find(".client_birth_province_id select option[value='#{province.id}']", visible: false).select_option

      # (Village/Commune — Cambodia-era address fields — are gone from the SLO4HOME form)
      click_button 'Save'
      wait_for_ajax
      expect(page).to have_content("The client you are registering has many attributes that match a client who is already registered at")
    end
  end

  feature 'Update', js: true do
    let!(:client){ create(:client, users: [user]) }
    before do
      login_as(user)
      visit edit_client_path(client)
    end
    scenario 'valid', js: true do
      fill_in 'Given Name', with: 'Allen'
      click_button 'Save'
      wait_for_ajax
      expect(page).to have_content('Allen')
    end

    xscenario 'invalid' do
      fill_in 'Given Name', with: ''
      click_button 'Save'
      expect(page).to have_content("can't be blank")
    end
  end

  feature 'Delete', js: true do
    # UX rung 2/4: delete lives in the hub header's Edit dropdown on the show page.
    let!(:client){ create(:client, users: [user]) }
    before do
      login_as(user)
      visit client_path(client)
    end
    scenario 'successfully' do
      find('.client-hub__edit .dropdown-toggle').click
      first("a[data-method='delete'][href='#{client_path(client.reload)}']").click
      sleep 1
      expect(page).to have_content('Client has been successfully deleted')
    end
  end

  feature 'Accept' do
    let!(:client){create(:client, users: [user])}
    before do
      login_as(user)
      visit client_path(client)
      click_button 'Accept'
    end
    scenario 'has new case note link' do
      expect(page).not_to have_link("Priority Intake Case") # polish: single Add to Household action
      expect(page).not_to have_link("Sponsor Care Case") # polish: single Add to Household action
      expect(page).to have_link("Add to Household")
    end
  end

  feature 'Reject' do
    let!(:client){create(:client, users: [user])}
    before do
      login_as(user)
      visit client_path(client)
      click_button 'Reject'

      fill_in 'Note', with: 'Rejected'
      find("input[type='submit'][value='Reject']").click
    end
    scenario 'successfully', js: true do
      wait_for_ajax
      expect(page).to have_content('Rejected')
    end
  end

  feature 'Accept and Reject' do
    let!(:non_status_client){ create(:client, state: '', users: [user]) }
    let!(:rejected_client){ create(:client, state: 'rejected', rejected_note: 'Something', users: [user]) }
    before do
      login_as(user)
    end
    scenario 'both button' do
      visit client_path(non_status_client)
      expect(page).to have_css("input[type='submit'][value='Accept']")
      expect(page).to have_css("input[type='submit'][value='Reject']")
    end

    scenario 'no rejected button' do
      visit client_path(rejected_client)
      expect(page).not_to have_css("input[type='submit'][value='Reject']")
    end
  end

  feature 'List Case' do
    let!(:accepted_client){ create(:client, state: 'accepted', users: [user]) }

    feature 'All Case' do
      let!(:emergency_case){ create(:case, case_type: 'EC', client: accepted_client) }
      let!(:foster_case){ create(:case, case_type: 'FC', client: accepted_client) }
      let!(:kinship_case){ create(:case, case_type: 'KC', client: accepted_client) }

      before do
        login_as(user)
        visit client_path(accepted_client)
      end

      # UX round 3 (A2): the Resettlement Case card folded into the About table as rows
      # (Resettlement case / Intake date / Case household). Only the CURRENT case (the most
      # recent active one) is summarized — the per-type card stack is gone.
      scenario 'All Panel' do
        expect(page).to have_css('dt', text: /\ACase\z/)
      end

      scenario 'Current case info' do
        current_case = accepted_client.cases.exclude_referred.current
        expect(page).to have_content('Intake date')
        expect(page).to have_content(current_case.start_date.strftime('%d %B, %Y'))
      end
    end

    feature 'Emergency Case' do
      let!(:emergency_case){ create(:case, case_type: 'EC', client: accepted_client) }

      before do
        login_as(user)
        visit client_path(accepted_client)
      end

      scenario 'Emergency Case panel' do
        expect(page).to have_css('dt', text: /\ACase\z/)
      end

      # (the case-type labels are unified now — "exactly one case panel" replaces the
      # old absent-type-label assertions)
      scenario 'No Foster and Kinship case panel' do
        expect(page).to have_content('Intake date', count: 1)
      end
    end
    feature 'Foster Case' do
      let!(:foster_case){ create(:case, case_type: 'FC', client: accepted_client) }

      before do
        login_as(user)
        visit client_path(accepted_client)
      end

      scenario 'Foster Case panel' do
        expect(page).to have_css('dt', text: /\ACase\z/)
      end

      scenario 'No Kinship and Emergency case panel' do
        expect(page).to have_content('Intake date', count: 1)
      end
    end
    feature 'Kinship Case' do
      let!(:kinship_case){ create(:case, case_type: 'KC', client: accepted_client) }

      before do
        login_as(user)
        visit client_path(accepted_client)
      end

      scenario 'Kinship Case panel' do
        expect(page).to have_css('dt', text: /\ACase\z/)
      end

      scenario 'No Foster and Emergency case panel' do
        expect(page).to have_content('Intake date', count: 1)
      end
    end
  end

  feature 'Case Button' do
    feature 'Blank Client' do
      let!(:blank_client){ create(:client, state: 'accepted', users: [user]) }

      before do
        login_as(user)
        visit client_path(blank_client)
      end

      scenario 'Emergency Case Button' do
        expect(page).not_to have_link("Priority Intake Case") # polish: single Add to Household action
      end

      scenario 'Foster Case Button' do
        expect(page).not_to have_link("Sponsor Care Case") # polish: single Add to Household action
      end

      scenario 'Kinship Case Button' do
        expect(page).to have_link("Add to Household")
      end

      scenario 'Exit Organization Button' do
        expect(page).to have_content('Exit From Organization')
      end
    end

    feature 'Emergency Active Client' do
      let!(:ec_client){ create(:client, state: 'accepted', users: [user]) }
      let!(:case){ create(:case, case_type: 'EC', client: ec_client, exited: false) }

      before do
        login_as(user)
        visit client_path(ec_client)
      end

      scenario 'Emergency Case Button' do
        expect(page).not_to have_link('Priority Intake Case')
      end

      scenario 'Foster Case Button' do
        expect(page).not_to have_link('Sponsor Care Case')
      end

      scenario 'Kinship Case Button' do
        expect(page).not_to have_link("Add to Household")
      end

      scenario 'Exit From EC' do
        exit_case_button = find('.exit-case-warning')
        expect(exit_case_button).to have_content(I18n.t('clients.show.exit_from_ec'))
      end
    end

    feature 'Active Foster Client' do
      let!(:fc_client){ create(:client, state: 'accepted', users: [user]) }
      let!(:case){ create(:case, case_type: 'FC', client: fc_client, exited: false) }

      before do
        login_as(user)
        visit client_path(fc_client)
      end
      scenario 'FC' do
        exit_case_button = find('.exit-case-warning')
        expect(exit_case_button).to have_content(I18n.t('clients.show.exit_from_fc'))
      end
    end

    feature 'Active Kinship Client' do
      let!(:kc_client){ create(:client, state: 'accepted', users: [user]) }
      let!(:case){ create(:case, case_type: 'KC', client: kc_client, exited: false) }

      before do
        login_as(user)
        visit client_path(kc_client)
      end
      scenario 'KC' do
        exit_case_button = find('.exit-case-warning')
        expect(exit_case_button).to have_content(I18n.t('clients.show.exit_from_kc'))
      end
    end

    feature 'Not Emergency Active Client' do
      let!(:active_client){ create(:client, state: 'accepted', users: [user]) }
      let!(:case){ create(:case, case_type: ['FC', 'KC'].sample, client: active_client, exited: false) }

      before do
        login_as(user)
        visit client_path(active_client)
      end

      scenario 'Emergency Case Button' do
        expect(page).not_to have_link('Priority Intake Case')
      end

      scenario 'Foster Case Button' do
        expect(page).not_to have_link('Sponsor Care Case')
      end

      scenario 'Kinship Case Button' do
        expect(page).not_to have_link("Add to Household")
      end
    end
    feature 'Inactive Client' do
      let!(:inactive_client){ create(:client, state: 'accepted', users: [user]) }
      let!(:case){ create(:case, :inactive, case_type: ['EC', 'FC', 'KC'].sample, client: inactive_client) }

      before do
        login_as(user)
        visit client_path(inactive_client)
      end

      scenario 'Emergency Case Button' do
        expect(page).not_to have_link("Priority Intake Case") # polish: single Add to Household action
      end

      scenario 'Foster Case Button' do
        expect(page).not_to have_link("Sponsor Care Case") # polish: single Add to Household action
      end
      scenario 'Kinship Case Button' do
        expect(page).to have_link("Add to Household")
      end
    end
  end

  feature 'Qualify Report' do
    let!(:accepted_client){ create(:client, state: 'accepted', users: [user]) }
    let!(:client_case){ create(:case, case_type: 'KC', client: accepted_client) }
    let!(:quarterly_report){ create(:quarterly_report, case: client_case) }
    before do
      login_as(admin)
      visit client_path(accepted_client)
    end
    scenario 'view link' do
      expect(page).to have_link('Legacy Quarterly Reports')
    end
  end

  feature 'Exit Case' do
    let(:accepted_client) { create(:client, state: 'accepted', users: [user]) }
    let!(:client_case) { create(:case, case_type: ['EC', 'FC', 'KC'].sample, client: accepted_client) }

    before do
      login_as(user)
      visit client_path(accepted_client)
    end
    # UX round 3 (A2): the case card's Exit button is gone — the exit modal opens from the
    # hub header's Actions dropdown item ("Close Resettlement Case").
    scenario 'Exit item in the Actions dropdown' do
      item = find("a[data-bs-target='#exit-from-case']")
      expect(item).to have_content('Close Case')
    end
    scenario 'Note', js: true do
      find('.client-hub__edit .dropdown-toggle').click
      page.find("a[data-bs-target='#exit-from-case']").click
      page.find(:css, '#exit-from-case')
      within '#exit-from-case' do
        fill_in 'Exit Date', with: '2017-07-07'
        fill_in 'Exit Note', with: FFaker::Lorem.paragraph
      end
      page.find("input[type='submit'][value='Exit']").click
      expect(page).to have_content('Referred')
    end
  end

  feature 'Time in care' do
    let!(:accepted_client) { create(:client, state: 'accepted', users: [user]) }
    before do
      login_as(user)
    end
    scenario 'without any cases' do
      visit client_path(accepted_client)
      time_in_care = accepted_client.time_in_care
      expect(time_in_care).to be_nil
      expect(page).to have_content(time_in_care)
    end

    scenario 'with case' do
      Case.create(case_type: 'EC', client: accepted_client, exited: false, start_date: 1.year.ago)

      visit client_path(accepted_client)
      # BS5-Q3: the streamlined SLO4HOME show page no longer prints time-in-care;
      # keep the calculation covered (the page renders without it).
      expect(accepted_client.time_in_care).to eq(1.0)
      expect(page).to have_css('dt', text: /\ACase\z/)
    end
  end

  feature 'Enable Edit Emergency Care' do
    let!(:accepted_client) { create(:client, state: 'accepted', users: [user]) }
    let!(:ec_case){ create(:case, case_type: 'EC', client: accepted_client) }
    let!(:kc_manager){ create(:user, roles: 'kc manager') }
    feature 'of active EC and FC/KC client' do
      feature 'login as case worker' do
        let!(:fc_case){ create(:case, case_type: 'FC', client: accepted_client) }
        before do
          login_as(kc_manager)
          visit client_path(accepted_client)
        end
        it { expect(page).not_to have_link(nil, href: edit_client_case_path(ec_case.client, ec_case)) }
      end

      feature 'login as admin' do
        let!(:kc_case){ create(:case, case_type: 'KC', client: accepted_client) }
        before do
          login_as(admin)
          visit client_path(accepted_client)
        end
        # UX round 3 (A2): "Edit Resettlement Case" lives in the header Actions dropdown and
        # targets the CURRENT (most recent active) case — the KC here, not the older EC (the
        # per-case-type card stack with an edit button per case is gone).
        it { expect(page).to have_link(nil, href: edit_client_case_path(accepted_client, kc_case)) }
        it { expect(page).not_to have_link(nil, href: edit_client_case_path(accepted_client, ec_case)) }
      end
    end
  end
end
