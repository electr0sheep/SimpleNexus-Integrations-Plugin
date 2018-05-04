class EncompassBrokerPuller

  ActiveRecordSlave.read_from_master!


  # split out for easier testing.
  def self.update_remote_loans(los, loans, servicer_input)
    # puts parsed_json
    # Rails.logger.info parsed_json
    failed_loans = []
    updated_loans = []

    # encompass_form integration updates milestones in separate call
    do_milestone_update = los.name != 'encompass_form'
    loans.each do |loan|
      begin
        #Rails.logger.info "loading #{loan.to_json}"
        if servicer_input == nil
          servicer = ServicerProfile.joins(:user).where(users: {email: loan['loan_officer_email']}, allow_loan_auto_connect: true ).first if ( loan['loan_officer_email'] )

          if servicer.blank?
            # there are times when the los has multiple accounts that a servicer uses.  In those cases, we need to create an alias.
            # at present, only servicers can have aliases.
            los_alias = UserAccountAlias.find_by_username_alias(loan['loan_officer_email'])
            if los_alias
              servicer = los_alias.user.servicer_profile
            end
          end

          if servicer.blank? && loan['los_user_id'].present? && los.company.present?
            servicer = ServicerProfile.joins(:user).where(users: {company_id: los.company.id}, 'los_user_id': loan['los_user_id']).first
          end
        elsif servicer_input != nil && servicer_input.allow_loan_auto_connect
          servicer = servicer_input
        end

        au = nil
        app_users = []

        if loan['borrower'] && loan['borrower']['app_user_id'] && loan['borrower']['app_user_id'] != -1
          app_users = AppUser.joins(:user).includes(:servicer_activation_code, {servicer_profile: {user: :company}})
                        .where(:id => "#{loan['borrower']['app_user_id']}", users: {company_id: los.company.id})
        elsif servicer
          query_app_users = servicer.app_users
                              .includes(:user, :servicer_activation_code, {servicer_profile: {user: :company}})
                              .where(users: {company_id: los.company.id})
          app_users = []
          query_app_users.each do |app_user|
            if app_user.email.present? && app_user.email == loan['borrower']['email_address']
              app_users << app_user
            elsif app_user.user&.unformatted_phone&.present? && app_user.user&.unformatted_phone == unformat_phone(loan['borrower']['phone'])
              app_users << app_user
            elsif app_user.user&.unformatted_phone&.present? && app_user.user&.unformatted_phone == unformat_phone(loan['borrower']['cell_phone'])
              app_users << app_user
            elsif app_user.user&.unformatted_office_phone&.present? && app_user.user&.unformatted_office_phone == unformat_phone(loan['borrower']['work_phone'])
              app_users << app_user
            end
          end
        else
          app_users = AppUser.joins(:user).includes(:servicer_activation_code, {servicer_profile: {user: :company}})
                             .where(users: {email: loan['borrower']['email_address'], company_id: los.company.id}) if loan['borrower']['email_address'].present?
          app_users += AppUser.joins(:user).includes(:servicer_activation_code, {servicer_profile: {user: :company}})
                         .where("users.account_type = 'app_user' and users.unformatted_phone is not null and users.unformatted_phone != '' and users.unformatted_phone in (?, ?, ?)", unformat_phone(loan['borrower']['phone']), unformat_phone(loan['borrower']['cell_phone']), unformat_phone(loan['borrower']['work_phone']))
                         .where(users: {company_id: los.company.id})
          app_users = app_users.uniq
        end

        app_users.each do |app_user|
          if app_user.servicer_activation_code.servicer_profile.company == los.company
            Rails.logger.info "found company los: #{los.company.id.to_s}"
            au = app_user
            Rails.logger.info  "au: #{au.id.to_s}"
            break
          end
        end

        # always update the remote loan.
        rl = nil
        rlb = nil
        rlcb = nil
        rlp = nil
        rl_buyer_agent = nil
        rl_seller_agent = nil
        existing_remote_loan = RemoteLoan.find_by_remote_id_and_loan_los_id(loan['remote_id'], los.id)
        if existing_remote_loan.blank?
          rlb = RemoteLoanBorrower.new
          if loan['co_borrower'] && loan['co_borrower'].size > 0
            rlcb = RemoteLoanBorrower.new
          end

          rlp = RemoteLoanProperty.new
          rlp.name = "#{loan['borrower']['first_name']} #{loan['borrower']['last_name']}"
          rl = RemoteLoan.new
          # puts 'new loan'
        else
          rl = existing_remote_loan
          rlb = existing_remote_loan.remote_loan_borrower
          rl_buyer_agent = existing_remote_loan.buyer_agent
          rl_seller_agent = existing_remote_loan.seller_agent
          rlcb = existing_remote_loan.remote_loan_co_borrower
          rlp = existing_remote_loan.remote_loan_property

          if rlp == nil
            rlp = RemoteLoanProperty.new
          end

          if rlb == nil && loan['borrower'] && loan['borrower'].size > 0 && loan['borrower']['first_name'].present?
            rlb = RemoteLoanBorrower.new
          end

          if rlcb == nil && loan['co_borrower'] && loan['co_borrower'].size > 0 && loan['co_borrower']['first_name'].present?
            rlcb = RemoteLoanBorrower.new
          end

        end

        rl = update_remote_loan(loan, rl, servicer, los)

        if loan['property'] && loan['property'].any?
          rlp = update_remote_loan_prop(loan, rlp, rl)
        end

        # Only create a borrower if there's some data
        if loan['borrower'] && loan['borrower'].size > 0 && loan['borrower']['first_name'].present?
          rlb = update_remote_loan_borr(loan, rlb, rl)
        end

        if loan['co_borrower'] && loan['co_borrower'].size > 0 && loan['co_borrower']['first_name'].present?
          rlcb = update_remote_loan_co_borr(loan, rlcb, rl)
        else
          rl.remote_loan_co_borrower.destroy if rl.remote_loan_co_borrower
        end

        create_or_update_remote_alerts(loan, rl)
        create_or_update_remote_milestone_events(loan, rl)

        buyer_agent = create_or_update_remote_partner(loan, servicer, "buyer_agent", rl)
        if buyer_agent && servicer && au
          partner = servicer.partners.find_by(:email => buyer_agent.email)
          if partner
            au.servicer_activation_code = partner.servicer_activation_code
          end
        end

        seller_agent = create_or_update_remote_partner(loan, servicer, "seller_agent", rl)
        
        # attempt to link up existing loans with the new remote loan. So if the user started the loan before we
        # had the data, we may find it here
        sac = au!=nil && au.servicer_activation_code

        if rl.loan.blank? && rl.remote_id.present?
          #Rails.logger.info { "Unable to find loan for remote_loan #{rl.remote_id} based on remote_id, starting search based on loan_number" }
          if servicer && rl.loan_number.present?
            found_loan = Loan.where(:loan_number => rl.loan_number, :servicer_profile => servicer).first
            Rails.logger.info { "Found loan from servicer. Loan: #{found_loan.id} -- Servicer: #{servicer.id} -- RemoteLoan Number: #{rl.loan_number}" } if found_loan.present?
          elsif sac && rl.loan_number.present?
            found_loan = Loan.where(:loan_number => rl.loan_number, :servicer_profile => sac.servicer_profile).first
            Rails.logger.info { "Found loan from servicer_activation_code. ServicerActivationCode: #{sac.id} -- RemoteLoan Number: #{rl.loan_number}" } if found_loan.present?
          end

          if !found_loan && servicer && loan['borrower'] && loan['borrower']['app_user_id'] && au.present?
            # used for update_encompass_loan to auto-create a loan for an app user if necessary.
            created_loan = Loan.create_loan_from_remote(rl, servicer, au)
            Rails.logger.info "Created new loan for app_user #{au&.id} -- Loan: #{created_loan.id}"
          end

          rl.loan = (found_loan || created_loan)

          rl.save!
          # since we just saved the object, force the read from the slave so we can guarantee we have the record
          ActiveRecordSlave.read_from_master do
            rl.reload
          end
          # update milestones with the new found/created loan
          update_remote_milestones(rl) if do_milestone_update

        end


        if rl.loan.present?
          Rails.logger.info { "Updating remote_loan #{rl.id}'s loan (#{rl.loan.id}) to match new RemoteLoan information" }
          # it's possible the app user info in the LOS changed from the app user in our system.
          au = rl.loan&.borrower&.app_user
          # update the local loan if it exists

          rl.loan.loan_number = rl.loan_number
          rl.loan.loan_program = rl.loan_program
          rl.loan.loan_purpose = rl.loan_purpose
          rl.loan.loan_folder = rl.loan_folder
          rl.loan.loan_amount = rl.loan_amount
          rl.loan.active = rl.active
          rl.loan.display = rl.active
          rl.loan.loan_type = rl.loan_type
          rl.loan.loan_term = rl.loan_term
          rl.loan.property_type = rl.property_type
          rl.loan.occupancy_status = rl.occupancy_status
          rl.loan.interest_rate = rl.interest_rate
          rl.loan.amortization_type = rl.amortization_type
          rl.loan.loan_amount_total = rl.loan_amount_total
          rl.loan.downpayment_pct = rl.downpayment_pct
          rl.loan.downpayment_amount = rl.downpayment_amount
          rl.loan.existing_lien_amt = rl.existing_lien_amt
          rl.loan.proposed_monthly_mtg = rl.proposed_monthly_mtg
          rl.loan.proposed_monthly_otherfin = rl.proposed_monthly_otherfin
          rl.loan.proposed_monthly_hazins = rl.proposed_monthly_hazins
          rl.loan.proposed_monthly_taxes = rl.proposed_monthly_taxes
          rl.loan.proposed_monthly_mtgins = rl.proposed_monthly_mtgins
          rl.loan.proposed_monthly_hoa = rl.proposed_monthly_hoa
          rl.loan.proposed_monthly_other = rl.proposed_monthly_other
          rl.loan.total_monthly_pmt = rl.total_monthly_pmt
          rl.loan.p_and_i_payment = rl.p_and_i_payment
          rl.loan.payment_frequency = rl.payment_frequency
          rl.loan.total_payment_le = rl.total_payment_le
          rl.loan.total_payment_cd = rl.total_payment_cd
          rl.loan.initial_le_sent = rl.initial_le_sent
          rl.loan.initial_le_received = rl.initial_le_received
          rl.loan.revised_le_sent = rl.revised_le_sent
          rl.loan.revised_le_received = rl.revised_le_received
          rl.loan.initial_cd_sent = rl.initial_cd_sent
          rl.loan.initial_cd_received = rl.initial_cd_received
          rl.loan.revised_cd_sent = rl.revised_cd_sent
          rl.loan.revised_cd_received = rl.revised_cd_received
          rl.loan.approved_date = rl.approved_date
          rl.loan.cash_from_borrower = rl.cash_from_borrower
          rl.loan.closing_date = rl.closing_date
          rl.loan.remote_id = rl.remote_id
          rl.loan.appraisal_received_date = get_date_with_time( get_time( rl.appraisal_received_date ) ) if rl.loan.appraisal_received_date.blank?
          rl.loan.appraisal_ordered_date = get_date_with_time( get_time( rl.appraisal_ordered_date ) ) if rl.loan.appraisal_ordered_date.blank?
          rl.loan.appraisal_reviewed_date = get_date_with_time( get_time( rl.appraisal_reviewed_date ) ) if rl.loan.appraisal_reviewed_date.blank?
          rl.loan.intent_to_proceed_letter_sent_date = get_date_with_time( get_time( rl.intent_to_proceed_letter_sent_date ) ) if rl.loan.intent_to_proceed_letter_sent_date.blank?
          rl.loan.closing_disclosure_sent_date = get_date_with_time( get_time( rl.closing_disclosure_sent_date ) ) if rl.loan.closing_disclosure_sent_date.blank?
          rl.loan.approved_date = rl.approved_date if rl.loan.approved_date.blank?
          rl.loan.total_monthly_pmt = rl.total_monthly_pmt
          rl.loan.apr = rl.apr
          rl.loan.lien_position = rl.lien_position
          rl.loan.second_lien_amt = rl.second_lien_amt
          rl.loan.heloc_limit = rl.heloc_limit
          rl.loan.heloc_balance = rl.heloc_balance
          rl.loan.aus_name = rl.aus_name
          rl.loan.dti_low = rl.dti_low
          rl.loan.dti_high = rl.dti_high
          rl.loan.refi_cashout_amt = rl.refi_cashout_amt
          rl.loan.escrows_waived = rl.escrows_waived
          rl.loan.first_time_buyer = rl.first_time_buyer
          rl.loan.loan_amount_base = rl.loan_amount_base
          rl.loan.cash_to_close = rl.cash_to_close
          rl.loan.veteran_buyer = rl.veteran_buyer
          rl.loan.estimated_cash_to_close = rl.estimated_cash_to_close
          rl.loan.dti_high = rl.dti_high
          rl.loan.ltv_pct = rl.ltv_pct
          rl.loan.cltv_pct = rl.cltv_pct
          rl.loan.tltv_pct = rl.tltv_pct
          rl.loan.representative_fico = rl.representative_fico
          rl.loan.intent_to_proceed = rl.intent_to_proceed
          rl.loan.p_and_i_payment = rl.p_and_i_payment
          rl.loan.credit_report_expiration_date = rl.credit_report_expiration_date
          rl.loan.prequal_allowed = rl.prequal_allowed
          rl.loan.preapproval_allowed = rl.preapproval_allowed
          rl.loan.rate_locked = rl.rate_locked
          rl.loan.rate_expiration_time = rl.rate_expiration_time


          #Fairway AZ Letter
          rl.loan.relying_on_sale_or_lease_to_qualify = rl.relying_on_sale_or_lease_to_qualify
          rl.loan.relying_on_seller_concessions = rl.relying_on_seller_concessions
          rl.loan.relying_on_down_payment_assistance = rl.relying_on_down_payment_assistance
          rl.loan.lender_has_provided_hud_form_for_fha_loans = rl.lender_has_provided_hud_form_for_fha_loans
          rl.loan.verbal_discussion_of_income_assets_and_debts = rl.verbal_discussion_of_income_assets_and_debts
          rl.loan.lender_has_obtained_tri_merged_residential_credit_report = rl.lender_has_obtained_tri_merged_residential_credit_report
          rl.loan.lender_has_received_paystubs = rl.lender_has_received_paystubs
          rl.loan.lender_has_received_w2s = rl.lender_has_received_w2s
          rl.loan.lender_has_received_personal_tax_returns = rl.lender_has_received_personal_tax_returns
          rl.loan.lender_has_received_corporate_tax_returns = rl.lender_has_received_corporate_tax_returns
          rl.loan.lender_has_received_down_payment_reserves_documentation = rl.lender_has_received_down_payment_reserves_documentation
          rl.loan.lender_has_received_gift_documentation = rl.lender_has_received_gift_documentation
          rl.loan.lender_has_received_credit_liability_documentation = rl.lender_has_received_credit_liability_documentation
          rl.loan.additional_comments = rl.additional_comments
          rl.loan.expiration_date = rl.expiration_date

          #checkpoint save - temp while I watch for some other errors
          rl.save!

          rl.loan.borrower.first_name = rlb&.first_name
          rl.loan.borrower.last_name = rlb&.last_name
          rl.loan.borrower.home_phone = rlb&.cell_phone
          rl.loan.borrower.cell_phone = rlb&.cell_phone
          rl.loan.borrower.work_phone = rlb&.work_phone
          rl.loan.borrower.email = rlb&.email
          rl.loan.borrower.credit_score = rlb&.credit_score
          rl.loan.borrower.econsent_status = rlb&.econsent_status
          rl.loan.borrower.credit_ref_number = rlb&.credit_ref_number
          rl.loan.borrower.credit_auth = rlb&.credit_auth
          rl.loan.borrower.self_employed = rlb&.self_employed
          rl.loan.borrower.dob = rlb&.dob
          rl.loan.borrower.ssn = rlb&.ssn

          rl.loan.borrower.street1 = rlb&.street1
          rl.loan.borrower.street2 = rlb&.street2
          rl.loan.borrower.city = rlb&.city
          rl.loan.borrower.state = rlb&.state
          rl.loan.borrower.zip = rlb&.zip

          if rlcb && !rl.loan.co_borrower  # this is copied from Loan.rb. We might have created a loan before we had the coborrower information
            Rails.logger.info { "No co-borrower on the SN system found for RemoteLoanBorrower (coborrower): #{rlcb.id} -- Creating a new one." }
            lcb = LoanBorrower.new
            lcb.first_name = rlcb.first_name
            lcb.last_name = rlcb.last_name
            lcb.credit_score = rlcb.credit_score
            lcb.econsent_status = rlcb.econsent_status
            lcb.email = rlcb.email
            lcb.home_phone = rlcb.cell_phone #should convert to using home_phone 8/28/2016
            lcb.cell_phone = rlcb.cell_phone
            lcb.work_phone = rlcb.work_phone
            lcb.dob = rlcb.dob
            lcb.ssn = rlcb.ssn
            lcb.credit_score = rlcb.credit_score
            lcb.econsent_status = rlcb.econsent_status
            lcb.credit_ref_number = rlcb.credit_ref_number
            lcb.credit_auth = rlcb.credit_auth
            lcb.self_employed = rlcb.self_employed
            lcb.street1 = rlcb.street1
            lcb.street2 = rlcb.street2
            lcb.city = rlcb.city
            lcb.state = rlcb.state
            lcb.zip = rlcb.zip

            lcb.co_borrower = true
            lcb.save!
            ActiveRecordSlave.read_from_master do
              lcb.reload
            end

            rl.loan.co_borrower = lcb
            rl.loan.co_borrower.save!
          elsif rlcb && rl.loan.co_borrower #update the loan borrower info we just got from the LOS
            Rails.logger.info { "Co-borrower found for RemoteLoan #{rl.id} -- RemoteLoanBorrower: #{rlcb.id} -- CoBorrower: #{rl.loan.co_borrower.id}" }
            rl.loan.co_borrower.first_name = rlcb.first_name
            rl.loan.co_borrower.last_name = rlcb.last_name
            rl.loan.co_borrower.home_phone = rlcb.cell_phone
            rl.loan.co_borrower.cell_phone = rlcb.cell_phone
            rl.loan.co_borrower.work_phone = rlcb.work_phone
            rl.loan.co_borrower.email = rlcb.email
            rl.loan.co_borrower.credit_score = rlcb.credit_score
            rl.loan.co_borrower.econsent_status = rlcb.econsent_status
            rl.loan.co_borrower.credit_ref_number = rlcb.credit_ref_number
            rl.loan.co_borrower.credit_auth = rlcb.credit_auth
            rl.loan.co_borrower.self_employed = rlcb.self_employed
            rl.loan.co_borrower.dob = rlcb.dob
            rl.loan.co_borrower.ssn = rlcb.ssn

            rl.loan.co_borrower.street1 = rlcb.street1
            rl.loan.co_borrower.street2 = rlcb.street2
            rl.loan.co_borrower.city = rlcb.city
            rl.loan.co_borrower.state = rlcb.state
            rl.loan.co_borrower.zip = rlcb.zip
          end

          sac = au&.servicer_activation_code
          if au.present? && sac.present?
            rl.loan.borrower.app_user = au
          end

          if rl.loan.loan_property.nil?
            rl.loan.loan_property = LoanProperty.new
          end

          if rl.loan.loan_property.present?
            rl.loan.loan_property.street = rlp.street
            rl.loan.loan_property.city = rlp.city
            rl.loan.loan_property.state = rlp.state
            rl.loan.loan_property.zip = rlp.zip
            rl.loan.loan_property.county = rlp.county
            rl.loan.loan_property.appraised_value = rlp.appraised_value
            rl.loan.loan_property.estimated_value = rlp.estimated_value
            rl.loan.loan_property.purchase_price = rlp.purchase_price
            rl.loan.loan_property.num_of_units = rlp.num_of_units
            rl.loan.loan_property.num_of_stories = rlp.num_of_stories
          end

          if rl.servicer_profile
            rl.loan.servicer_profile = rl.servicer_profile
          end

          if rl.loan.app_user && rl.servicer_profile && rl.loan.app_user.servicer_profile != rl.servicer_profile
            rl.loan.app_user.servicer_activation_code = rl.servicer_profile.default_code
            # is this save necessary?
            rl.loan.app_user.save!
          end

          create_or_update_loan_partner(loan, rl.loan.servicer_profile, "buyer_agent", rl)
          create_or_update_loan_partner(loan, rl.loan.servicer_profile, "seller_agent", rl)

          rl.loan.save!
          rl.save!
          ActiveRecordSlave.read_from_master do
            rl.reload
          end

          if do_milestone_update
            ms_response = update_remote_milestones(rl)

            # MILESTONE PUSHES
            if ms_response["ms_loan_definition"].present?
              rl.loan.send_milestone_progress_pushes_if_needed( ms_response["ms_loan_definition"] )
            end
          end
          Rails.logger.info "updated existing loan.id: #{rl.loan.id}; remote loan id: #{rl.id}"

        elsif au.present? && au.servicer_profile == servicer && rl.loan.blank? && !rl.association_emailed && rl.active && servicer.present? && servicer.user.active?
          # create the existing_remote_loan and notify LO
          # automatically link app user and remote loan
          # servicer.default_loan_milestones.any?{|dlm| dlm.name == rl.status || dlm.remote_name == rl.status}
          if au && servicer && servicer.company && servicer.company.auto_connect_app_user_to_loans?
            Rails.logger.info "automatically connecting app user #{au.email} to remote loan id #{rl.remote_id}"
            loan_record = Loan.create_loan_from_remote(rl, servicer, au)
            ms_response = update_remote_milestones(rl) if do_milestone_update
            Rails.logger.info "connected app user #{au.email} with new loan #{loan_record.id} from remote loan id #{rl.remote_id}"
            ConnectLoanToAppUserJob.perform_later(:remote_id => rl.remote_id,
                                                  :loan_number => rl.loan_number,
                                                  :app_user_name => au.name,
                                                  :app_user_phone => au.unformatted_phone,
                                                  :app_user_email => au.email,
                                                  :app_user_device => au.device_id,
                                                  :los_user_name => "#{loan['borrower']['first_name']} #{loan['borrower']['last_name']}",
                                                  :los_user_phone => "#{loan['borrower']['phone']}",
                                                  :los_user_cell_phone => "#{loan['borrower']['cell_phone']}",
                                                  :los_user_work_phone => "#{loan['borrower']['work_phone']}",
                                                  :los_user_email_address => "#{loan['borrower']['email_address']}")

            if do_milestone_update && rl.active && servicer.company.allow_loan_auto_connect_notifications?
              PushMessageRecord.notify(au.device_id, servicer, "Your loan has been connected to your app.", ms_response["milestone_action"], ms_response["milestone_name"], true, (au && au.user ? "user_#{au.user.id}" : nil) )
            end
            rl.association_emailed = true
            rl.save!
            ActiveRecordSlave.read_from_master do
              rl.reload
            end
          elsif servicer.default_loan_milestones.any?{|dlm| dlm.name == rl.status || dlm.remote_name == rl.status} && servicer.company && servicer.company.allow_loan_auto_connect_notifications?
            # only proceed if the imported loan milestone matches what we've stored.
            ::LosLoanAssociationJob.perform_later(:remote_id => rl.remote_id,
                                                  :loan_number => rl.loan_number,
                                                  :loan_guid => rl.remote_id,
                                                  :app_user_name => au.name,
                                                  :app_user_phone => au.unformatted_phone,
                                                  :app_user_email => au.email,
                                                  :app_user_device => au.device_id,
                                                  :los_user_name => "#{loan['borrower']['first_name']} #{loan['borrower']['last_name']}",
                                                  :los_user_phone => "#{loan['borrower']['phone']}",
                                                  :los_user_cell_phone => "#{loan['borrower']['cell_phone']}",
                                                  :los_user_work_phone => "#{loan['borrower']['work_phone']}",
                                                  :los_user_email_address => "#{loan['borrower']['email_address']}")

            rl.association_emailed = true
            rl.save!
            ActiveRecordSlave.read_from_master do
              rl.reload
            end

            Rails.logger.info "sent connection email for existing_remote_loan.id: #{rl.id} to #{loan['borrower']['email_address']}; remote loan number: #{rl.remote_id}"
          end
        elsif au.blank? && rl.loan.blank? && existing_remote_loan.blank? && rl.active && servicer.present? && servicer.user.active? && servicer.company&.allow_loan_invitation_notifications? && rlb.email.present?
          # 05/12/2016 - commented the following line as this would often be possible, but we want to still get the LO's to share the app.
          # if servicer.default_loan_milestones.any?{|dlm| dlm.name == rl.status || dlm.remote_name == rl.status} && servicer.company && servicer.company.allow_loan_invitation_notifications?
          # only proceed if the imported loan milestone matches what we've stored.
          BorrowerInvitationEmailJob.perform_later(:remote_id => rl.remote_id,
                                                   :loan_number => rl.loan_number,
                                                   :servicer_id => servicer.id,
                                                   :los_user_name => "#{loan['borrower']['first_name']} #{loan['borrower']['last_name']}",
                                                   :los_user_phone => "#{loan['borrower']['phone']}",
                                                   :los_user_cell => "#{loan['borrower']['cell_phone']}",
                                                   :los_user_work => "#{loan['borrower']['work_phone']}",
                                                   :los_user_email_address => "#{loan['borrower']['email_address']}")
        end

        updated_loans << rl

      rescue => ex
        NewRelic::Agent.notice_error( ex )
        Rails.logger.error ex
        puts "Backtrace:\n\t#{ex.backtrace.join("\n\t")}"
        failed_loans << loan
      end

      # we're looping; reset the servicer
      servicer = nil
    end

    unless failed_loans.empty?
      #SupportNotifications.notify_developers("Error updating loans: #{failed_loans}").deliver_now
    end

    updated_loans
  end

  def self.update_remote_milestones(remote_loan)
  	if remote_loan
  		ms_response = update_milestones(remote_loan, remote_loan.status)
  		if remote_loan.loan
  			update_milestones(remote_loan.loan, remote_loan.status)
  		end
  		ms_response
  	end
  end

  def self.update_milestones(loan_type, milestone_name)
    ms_name = milestone_name
    message = nil
    ms_loan_definition = nil
    ms_action = "view_milestones"

    ms_step = -1
    loan_type.sorted_loan_milestones.each do |ms|
      if ms_name == ms.loan_milestone_definition.remote_name || ms_name == ms.loan_milestone_definition.name
        ms_step = ms.loan_milestone_definition.step
      end
    end

    if ms_step > -1
      loan_type.sorted_loan_milestones.each do |ms|
        if ms.loan_milestone_definition.step <= ms_step
          if ms.status != 'complete'
            ms_loan_definition = ms.loan_milestone_definition
            if ms.message_sent
              ms_loan_definition = nil
            else
              message = ms_loan_definition.client_msg
              ms.message_sent = true
            end
          end
          ms.status = 'complete'
          ms.completed = true
        else
          ms.status = 'incomplete'
          ms.completed = false
        end

        ms.status_time = Time.now
        ms.save!
      end
    end

    if ms_loan_definition
      ms_action = ms_loan_definition.action_type
      if ms_loan_definition.action_details
        ms_name = ms_loan_definition.action_details
      end
    end

    {"message" => message, "milestone_action" => ms_action, "milestone_name" =>  ms_name, "ms_loan_definition" => ms_loan_definition}

  end


  def self.update_remote_loan(loan, rl, servicer, los)
    rl.loan_los = los
    rl.loan_number = loan['loan_id']
    rl.remote_id = loan['remote_id']
    rl.loan_program = loan['loan_program']
    rl.loan_purpose = loan['loan_purpose']
    rl.loan_amount = loan['loan_amount']
    rl.loan_type = loan['loan_type']
    rl.property_type = loan['property_type']
    rl.occupancy_status = loan['occupancy_status']
    rl.loan_term = loan['loan_term']
    rl.interest_rate = loan['interest_rate']
    rl.amortization_type = loan['amortization_type']
    rl.loan_amount_total = loan['loan_amount_total']
    rl.downpayment_pct = loan['downpayment_pct']
    rl.downpayment_amount = loan['downpayment_amount']
    rl.existing_lien_amt = loan['existing_lien_amt']
    rl.proposed_monthly_mtg = loan['proposed_monthly_mtg']
    rl.proposed_monthly_otherfin = loan['proposed_monthly_otherfin']
    rl.proposed_monthly_hazins = loan['proposed_monthly_hazins']
    rl.proposed_monthly_taxes = loan['proposed_monthly_taxes']
    rl.proposed_monthly_mtgins = loan['proposed_monthly_mtgins']
    rl.proposed_monthly_hoa = loan['proposed_monthly_hoa']
    rl.proposed_monthly_other = loan['proposed_monthly_other']
    rl.total_monthly_pmt = loan['total_monthly_pmt']
    rl.p_and_i_payment = loan['p_and_i_payment']
    rl.payment_frequency = loan['payment_frequency']
    rl.total_payment_le = loan['total_payment_le']
    rl.total_payment_cd = loan['total_payment_cd']
    rl.initial_le_sent = loan['initial_le_sent']
    rl.initial_le_received = loan['initial_le_received']
    rl.revised_le_sent = loan['revised_le_sent']
    rl.revised_le_received = loan['revised_le_received']
    rl.initial_cd_sent = loan['initial_cd_sent']
    rl.initial_cd_received = loan['initial_cd_received']
    rl.revised_cd_sent = loan['revised_cd_sent']
    rl.revised_cd_received = loan['revised_cd_received']
    rl.approved_date = loan['approved_date']
    rl.cash_from_borrower = loan['cash_from_borrower']
    rl.closing_date = loan['closing_date']
    rl.created_remote_time = loan['remote_loan_created']
    rl.opened_remote_time = loan['remote_loan_created']
    rl.lien_position = loan['lien_position']
    rl.second_lien_amt = loan['second_lien_amt']
    rl.heloc_limit = loan['heloc_limit']
    rl.heloc_balance = loan['heloc_balance']
    rl.aus_name = loan['aus_name']
    rl.dti_low = loan['dti_low']
    rl.dti_high = loan['dti_high']
    rl.refi_cashout_amt = loan['refi_cashout_amt']
    rl.escrows_waived = loan['escrows_waived']
    rl.first_time_buyer = loan['first_time_buyer']
    rl.veteran_buyer = loan['veteran_buyer']
    rl.referral_source = loan['remote_referral_source']
    rl.status = loan['remote_loan_status']

    rl.loan_source = loan['remote_loan_source']
    rl.cash_from_borrower = loan['cash_from_borrower']
    rl.action_taken = loan['remote_loan_action_taken']
    rl.action_taken_date = loan['remote_loan_action_taken_date']
    if loan['remote_rate_locked'] && rl.rate_expiration_time != loan['remote_lock_expiration']
      # placeholder to send out rate lock alerts.
    end

    rl.rate_locked = loan['remote_rate_locked']
    rl.rate_expiration_time = loan['remote_lock_expiration']
    rl.econsent_date = loan['econsent_date']
    rl.intent_to_proceed = loan['intent_to_proceed']
    rl.closing_date = loan['closing_date']
    rl.last_doc_order_date = loan['last_doc_order_date']
    rl.doc_signing_date = loan['doc_signing_date']
    rl.funding_date = loan['funding_date']
    rl.estimated_completion = loan['remote_estimated_completion']
    rl.last_modified_time = loan['remote_last_modified']
    rl.loan_folder = loan['remote_loan_folder']

    if ! rl.appraisal_received_date && loan['appraisal_received_date'] && loan['appraisal_received_date'].present?
      rl.appraisal_received_date = loan['appraisal_received_date']

      # if get_date_without_time(rl.appraisal_received_date) == get_date_without_time(DateTime.now)
        rl.appraisal_received_date = DateTime.now
      # end
    end

    if ! rl.appraisal_ordered_date && loan['appraisal_ordered_date'] && loan['appraisal_ordered_date'].present?
      rl.appraisal_ordered_date = get_date_with_time( loan['appraisal_ordered_date'] )
    end

    if ! rl.appraisal_reviewed_date && loan['appraisal_reviewed_date'] && loan['appraisal_reviewed_date'].present?
      rl.appraisal_reviewed_date = get_date_with_time( loan['appraisal_reviewed_date'] )
    end

    if ! rl.closing_disclosure_sent_date && loan['closing_disclosure_sent_date'] && loan['closing_disclosure_sent_date'].present?
      rl.closing_disclosure_sent_date = get_date_with_time( loan['closing_disclosure_sent_date'] )
    end

    if rl.intent_to_proceed_letter_sent_date.blank? && loan['intent_to_proceed_letter_sent_date'] && loan['intent_to_proceed_letter_sent_date'].present?
      rl.intent_to_proceed_letter_sent_date = get_date_with_time( loan['intent_to_proceed_letter_sent_date'] )
    end

    if rl.approved_date.blank? && loan['approved_date'] && loan['approved_date'].present?
      rl.approved_date = loan['approved_date']
    end

    if loan['relying_on_sale_or_lease_to_qualify_yes'].present? && loan['relying_on_sale_or_lease_to_qualify_yes'].casecmp('x').zero?
      rl.relying_on_sale_or_lease_to_qualify = "Yes"
    end

    if loan['relying_on_sale_or_lease_to_qualify_no'].present? && loan['relying_on_sale_or_lease_to_qualify_no'].casecmp('x').zero?
      rl.relying_on_sale_or_lease_to_qualify = "No"
    end

    if loan['relying_on_seller_concessions_yes'].present? && loan['relying_on_seller_concessions_yes'].casecmp('x').zero?
      rl.relying_on_seller_concessions = "Yes"
    end

    if loan['relying_on_seller_concessions_no'].present? && loan['relying_on_seller_concessions_no'].casecmp('x').zero?
      rl.relying_on_seller_concessions = "No"
    end

    if loan['relying_on_down_payment_assistance_yes'].present? && loan['relying_on_down_payment_assistance_yes'].casecmp('x').zero?
      rl.relying_on_down_payment_assistance = "Yes"
    end

    if loan['relying_on_down_payment_assistance_no'].present? && loan['relying_on_down_payment_assistance_no'].casecmp('x').zero?
      rl.relying_on_down_payment_assistance = "No"
    end

    if loan['lender_has_provided_hud_form_for_fha_loans_yes'].present? && loan['lender_has_provided_hud_form_for_fha_loans_yes'].casecmp('x').zero?
      rl.lender_has_provided_hud_form_for_fha_loans = "Yes"
    end

    if loan['lender_has_provided_hud_form_for_fha_loans_no'].present? && loan['lender_has_provided_hud_form_for_fha_loans_no'].casecmp('x').zero?
      rl.lender_has_provided_hud_form_for_fha_loans = "No"
    end

    if loan['lender_has_provided_hud_form_for_fha_loans_na'].present? && loan['lender_has_provided_hud_form_for_fha_loans_na'].casecmp('x').zero?
      rl.lender_has_provided_hud_form_for_fha_loans = "N/A"
    end

    if loan['verbal_discussion_of_income_assets_and_debts_yes'].present? && loan['verbal_discussion_of_income_assets_and_debts_yes'].casecmp('x').zero?
      rl.verbal_discussion_of_income_assets_and_debts = "Yes"
    end

    if loan['verbal_discussion_of_income_assets_and_debts_no'].present? && loan['verbal_discussion_of_income_assets_and_debts_no'].casecmp('x').zero?
      rl.verbal_discussion_of_income_assets_and_debts = "No"
    end

    if loan['verbal_discussion_of_income_assets_and_debts_na'].present? && loan['verbal_discussion_of_income_assets_and_debts_na'].casecmp('x').zero?
      rl.verbal_discussion_of_income_assets_and_debts = "N/A"
    end

    if loan['lender_has_obtained_tri_merged_residential_credit_report_yes'].present? && loan['lender_has_obtained_tri_merged_residential_credit_report_yes'].casecmp('x').zero?
      rl.lender_has_obtained_tri_merged_residential_credit_report = "Yes"
    end

    if loan['lender_has_obtained_tri_merged_residential_credit_report_no'].present? && loan['lender_has_obtained_tri_merged_residential_credit_report_no'].casecmp('x').zero?
      rl.lender_has_obtained_tri_merged_residential_credit_report = "No"
    end

    if loan['lender_has_obtained_tri_merged_residential_credit_report_na'].present? && loan['lender_has_obtained_tri_merged_residential_credit_report_na'].casecmp('x').zero?
      rl.lender_has_obtained_tri_merged_residential_credit_report = "N/A"
    end

    if loan['lender_has_received_paystubs_yes'].present? && loan['lender_has_received_paystubs_yes'].casecmp('x').zero?
      rl.lender_has_received_paystubs = "Yes"
    end

    if loan['lender_has_received_paystubs_no'].present? && loan['lender_has_received_paystubs_no'].casecmp('x').zero?
      rl.lender_has_received_paystubs = "No"
    end

    if loan['lender_has_received_paystubs_na'].present? && loan['lender_has_received_paystubs_na'].casecmp('x').zero?
      rl.lender_has_received_paystubs = "N/A"
    end

    if loan['lender_has_received_w2s_yes'].present? && loan['lender_has_received_w2s_yes'].casecmp('x').zero?
      rl.lender_has_received_w2s = "Yes"
    end

    if loan['lender_has_received_w2s_no'].present? && loan['lender_has_received_w2s_no'].casecmp('x').zero?
      rl.lender_has_received_w2s = "No"
    end

    if loan['lender_has_received_w2s_na'].present? && loan['lender_has_received_w2s_na'].casecmp('x').zero?
      rl.lender_has_received_w2s = "N/A"
    end

    if loan['lender_has_received_personal_tax_returns_yes'].present? && loan['lender_has_received_personal_tax_returns_yes'].casecmp('x').zero?
      rl.lender_has_received_personal_tax_returns = "Yes"
    end

    if loan['lender_has_received_personal_tax_returns_no'].present? && loan['lender_has_received_personal_tax_returns_no'].casecmp('x').zero?
      rl.lender_has_received_personal_tax_returns = "No"
    end

    if loan['lender_has_received_personal_tax_returns_na'].present? && loan['lender_has_received_personal_tax_returns_na'].casecmp('x').zero?
      rl.lender_has_received_personal_tax_returns = "N/A"
    end

    if loan['lender_has_received_corporate_tax_returns_yes'].present? && loan['lender_has_received_corporate_tax_returns_yes'].casecmp('x').zero?
      rl.lender_has_received_corporate_tax_returns = "Yes"
    end

    if loan['lender_has_received_corporate_tax_returns_no'].present? && loan['lender_has_received_corporate_tax_returns_no'].casecmp('x').zero?
      rl.lender_has_received_corporate_tax_returns = "No"
    end

    if loan['lender_has_received_corporate_tax_returns_na'].present? && loan['lender_has_received_corporate_tax_returns_na'].casecmp('x').zero?
      rl.lender_has_received_corporate_tax_returns = "N/A"
    end

    if loan['lender_has_received_down_payment_reserves_documentation_yes'].present? && loan['lender_has_received_down_payment_reserves_documentation_yes'].casecmp('x').zero?
      rl.lender_has_received_down_payment_reserves_documentation = "Yes"
    end

    if loan['lender_has_received_down_payment_reserves_documentation_no'].present? && loan['lender_has_received_down_payment_reserves_documentation_no'].casecmp('x').zero?
      rl.lender_has_received_down_payment_reserves_documentation = "No"
    end

    if loan['lender_has_received_down_payment_reserves_documentation_na'].present? && loan['lender_has_received_down_payment_reserves_documentation_na'].casecmp('x').zero?
      rl.lender_has_received_down_payment_reserves_documentation = "N/A"
    end

    if loan['lender_has_received_gift_documentation_yes'].present? && loan['lender_has_received_gift_documentation_yes'].casecmp('x').zero?
      rl.lender_has_received_gift_documentation = "Yes"
    end

    if loan['lender_has_received_gift_documentation_no'].present? && loan['lender_has_received_gift_documentation_no'].casecmp('x').zero?
      rl.lender_has_received_gift_documentation = "No"
    end

    if loan['lender_has_received_gift_documentation_na'].present? && loan['lender_has_received_gift_documentation_na'].casecmp('x').zero?
      rl.lender_has_received_gift_documentation = "N/A"
    end

    if loan['lender_has_received_credit_liability_documentation_yes'].present? && loan['lender_has_received_credit_liability_documentation_yes'].casecmp('x').zero?
      rl.lender_has_received_credit_liability_documentation = "Yes"
    end

    if loan['lender_has_received_credit_liability_documentation_no'].present? && loan['lender_has_received_credit_liability_documentation_no'].casecmp('x').zero?
      rl.lender_has_received_credit_liability_documentation = "No"
    end

    if loan['lender_has_received_credit_liability_documentation_na'].present? && loan['lender_has_received_credit_liability_documentation_na'].casecmp('x').zero?
      rl.lender_has_received_credit_liability_documentation = "N/A"
    end

    rl.additional_comments = loan['additional_comments']
    rl.expiration_date = loan['expiration_date']
    rl.apr = loan['apr']
    rl.loan_amount_base = loan['loan_amount_base']
    rl.cash_to_close = loan['cash_to_close']
    rl.estimated_cash_to_close = loan['estimated_cash_to_close']
    rl.dti_high = loan['dti_high']
    rl.ltv_pct = loan['ltv_pct']
    rl.cltv_pct = loan['cltv_pct']
    rl.tltv_pct = loan['tltv_pct']
    rl.representative_fico = loan['representative_fico']
    rl.intent_to_proceed = loan['intent_to_proceed']
    rl.p_and_i_payment = loan['p_and_i_payment']
    rl.credit_report_expiration_date = loan['credit_report_expiration_date']

    rl.total_monthly_pmt = loan['total_monthly_pmt']
    rl.loan_officer_email = loan['loan_officer_email']
    rl.lo_nmls = loan['lo_nmls']
    rl.remote_user_id = loan['los_user_id']
    rl.loan_processor_email = loan['loan_processor_email']

    if loan['los_client_version'].present?
      rl.los_client_version = loan['los_client_version']
    end

    if loan['los_name'].present?
      rl.los_name = loan['los_name']
    end

    # Determine whether a prequal can be issued on a loan. Currently only working for Nations Lending
    if rl&.loan_los_id == 46 && (loan['prequal_allowed'].nil? || loan['prequal_allowed'].casecmp("x") != 0)
      rl.prequal_allowed = false
    elsif rl&.loan_los_id == 46 && loan['prequal_allowed'].present? && loan['prequal_allowed'].casecmp("x") == 0
      rl.prequal_allowed = true
    end

    # Determine whether a preapproval can be issued on a loan. Currently only working for Nations Lending
    if rl&.loan_los_id == 46 && (loan['preapproval_allowed'].nil? || loan['preapproval_allowed'].casecmp("x") != 0)
      rl.preapproval_allowed = false
    elsif rl&.loan_los_id == 46 && loan['preapproval_allowed'].present? && loan['preapproval_allowed'].casecmp("x") == 0
      rl.preapproval_allowed = true
    end

    # Determine whether a preapproval can be issued on a loan. For Synergy One
    if rl&.loan_los_id == 129
      if loan['preapproval_allowed'].present? && loan['preapproval_allowed'].casecmp("Y") == 0
        rl.preapproval_allowed = true
      else
        rl.preapproval_allowed = false
      end
    end

    # mortgage express
    # Determine whether a preapproval can be issued on a loan. Currently only working for Nations Lending
    # if rl&.loan_los_id == 58 && (loan['preapproval_allowed'].nil? || loan['preapproval_allowed'].casecmp("x") != 0)
    #   rl.preapproval_allowed = false
    # elsif rl&.loan_los_id == 58 && loan['preapproval_allowed'].present? && loan['preapproval_allowed'].casecmp("x") == 0
    #   rl.preapproval_allowed = true
    # end
    
    rl.servicer_profile = servicer

    # there are some remote statuses that should make the loan inactive.
    if rl.status && (los.company.remote_loan_inactive_statuses.pluck(:status_name)&[rl.status]).any?
      rl.active = false
      rl.display = rl.active
    end

    # However, (SEE ABOVE), if the milestone is defined as one for the borrower, make it active.
    # Ideally, both conditions will never be true.  If they are, this will win.
    los.company.loan_milestone_definitions.each do |ms|
      if ms.name == rl.status || ms.remote_name == rl.status
        rl.active = true
        rl.display = rl.active
        break
      end
    end

    # if it was Encompass, and a loan action was taken, deactivate the loan (but ignore ignorable statuses)
    if loan['remote_loan_action_taken'].present? && !(los.company.remote_loan_ignorable_loan_actions.pluck(:ignorable_loan_action_taken)&[loan['remote_loan_action_taken']]).any? && los.name == 'encompass_form'
      rl.active = false
      rl.display = rl.active
    end

    # if loan is now in an inactive folder, deactivate the loan
    if rl.loan_folder && (los.company.remote_loan_inactive_folders.pluck(:loan_folder)&[rl.loan_folder]).any?
      rl.active = false
      rl.display = rl.active
    end

    rl.save!
    ActiveRecordSlave.read_from_master do
      rl.reload
    end

  end

  def self.update_remote_loan_borr(loan, rlb, rl)
    #puts "creating_remote_loan_borr: #{loan['borrower']}\n#{rlb}\n#{rlb.first_name}"
    rlb.first_name = loan['borrower']['first_name']
    rlb.middle_name = loan['borrower']['middle_name']
    rlb.last_name = loan['borrower']['last_name']
    rlb.marital_status = loan['borrower']['marital_status']
    rlb.dob = loan['borrower']['dob']
    rlb.cell_phone = loan['borrower']['cell_phone']
    rlb.home_phone = loan['borrower']['phone']
    rlb.work_phone = loan['borrower']['work_phone']
    rlb.email = loan['borrower']['email_address']
    rlb.credit_score = loan['borrower']['credit_score']
    rlb.econsent_status = loan['borrower']['econsent_status']
    rlb.ssn = loan['borrower']['ssn'] if loan['borrower']['ssn'].present?

    rlb.street1 = loan['borrower']['street1']
    rlb.street2 = loan['borrower']['street2']
    rlb.city = loan['borrower']['city']
    rlb.state = loan['borrower']['state']
    rlb.zip = loan['borrower']['zip']

    rlb.credit_ref_number = loan['borrower']['credit_ref_number']
    rlb.self_employed = loan['borrower']['self_employed']
    rlb.credit_auth = loan['borrower']['credit_auth']
    rlb.co_borrower = false
    rlb.remote_loan_id = rl.id
    rlb.save!
    ActiveRecordSlave.read_from_master do
      rlb.reload
    end

    return rlb
  end

  def self.create_or_update_remote_partner(loan, servicer, partner_type, remote_loan)
    # we only want to redo the partner records if we have information from the LOS. Don't blindly delete the records as
    # we may have used the web to manually set the partners
    if partner_type.present? && loan[partner_type].present? && loan[partner_type]['email'].present?
      if partner_type == 'buyer_agent'
        remote_loan.buyer_agent.destroy if remote_loan.buyer_agent.present?
      else
        remote_loan.seller_agent.destroy if remote_loan.seller_agent.present?
      end

      # look for previous partner records; only proceed if we have the email at a minimum
      if loan && partner_type.present? && loan[partner_type].present? && loan[partner_type]['email'].present?

        rl_partner = RemoteLoanPartner.find_or_create_by(remote_loan_id: remote_loan.id, partner_type: partner_type)
        rl_partner.company_name = loan[partner_type]['company_name']
        rl_partner.street = loan[partner_type]['street']
        rl_partner.city = loan[partner_type]['city']
        rl_partner.state = loan[partner_type]['state']
        rl_partner.zip = loan[partner_type]['zip']
        rl_partner.company_license = loan[partner_type]['company_license']
        rl_partner.name = loan[partner_type]['name']
        rl_partner.phone = loan[partner_type]['phone']
        rl_partner.cell_phone = loan[partner_type]['cell_phone']
        rl_partner.email = loan[partner_type]['email']
        rl_partner.fax = loan[partner_type]['fax']
        rl_partner.agent_license = loan[partner_type]['agent_license']
        if servicer.present?
          rl_partner.partner = servicer.partners.where(email: rl_partner.email).first
        end
        rl_partner.save!
        ActiveRecordSlave.read_from_master do
          rl_partner.reload
        end

      end
    end
  end

  def self.create_or_update_loan_partner(loan, servicer, partner_type, remote_loan)
    # we only want to redo the partner records if we have information from the LOS. Don't blindly delete the records as
    # we may have used the web to manually set the partners
    if partner_type.present? && loan[partner_type].present? && loan[partner_type]['email'].present?

      if partner_type == 'buyer_agent'
        remote_loan.loan.buyer_agent.destroy if remote_loan.loan.buyer_agent.present?
      else
        remote_loan.loan.seller_agent.destroy if remote_loan.loan.seller_agent.present?
      end
      # look for previous partner records; only proceed if we have the email at a minimum
      if loan && servicer.present? && partner_type.present? && loan[partner_type].present? && loan[partner_type]['email'].present?

        loan_partner = LoanPartner.find_or_create_by(loan_id: remote_loan.loan.id, partner_type: partner_type)
        loan_partner.company_name = loan[partner_type]['company_name']
        loan_partner.street = loan[partner_type]['street']
        loan_partner.city = loan[partner_type]['city']
        loan_partner.state = loan[partner_type]['state']
        loan_partner.zip = loan[partner_type]['zip']
        loan_partner.company_license = loan[partner_type]['company_license']
        loan_partner.name = loan[partner_type]['name']
        loan_partner.phone = loan[partner_type]['phone']
        loan_partner.cell_phone = loan[partner_type]['cell_phone']
        loan_partner.email = loan[partner_type]['email']
        loan_partner.fax = loan[partner_type]['fax']
        loan_partner.agent_license = loan[partner_type]['agent_license']
        loan_partner.partner = servicer.partners.where(email: loan_partner.email).first
        loan_partner.save!
        ActiveRecordSlave.read_from_master do
          loan_partner.reload
        end

        if loan_partner.partner.present? && remote_loan.loan.borrower.present? && remote_loan.loan.borrower.app_user.present? && partner_type == "buyer_agent"
          au = remote_loan.loan.borrower.app_user
          au.servicer_activation_code = loan_partner.partner.servicer_activation_code
          au.save!
        end
        if loan_partner.partner.present? && remote_loan.loan.co_borrower.present? && remote_loan.loan.co_borrower.app_user.present? && partner_type == "buyer_agent"
          au = remote_loan.loan.co_borrower.app_user
          au.servicer_activation_code = loan_partner.partner.servicer_activation_code
          au.save!
        end
      end
    end
  end

  def self.create_or_update_remote_alerts(loan, remote_loan)
    if loan['alerts']
      loan['alerts'].each do |a|
        alert             = RemoteLoanAlert.find_or_create_by( remote_loan_id: remote_loan.id, alert_type: a['type'] )
        alert.alert_date  = a['date']
        alert.source      = a['source']
        alert.status      = a['status']
        alert.description = a['description']
        alert.save!
      end
    end
  end

  def self.create_or_update_remote_milestone_events(loan, remote_loan)
    if loan['milestone_events']
      loan['milestone_events'].each do |e|
        event                 = RemoteLoanMilestoneEvent.find_or_create_by( remote_loan_id: remote_loan.id, event_name: e['name'] )
        event.completed       = e['completed']
        event.status_date     = e['date']
        event.associate_name  = e['associate_name']
        event.associate_phone = e['associate_phone']
        event.associate_email = e['associate_email']
        event.associate_cell  = e['associate_cell']
        event.save!
      end
    end
  end

  def self.update_remote_loan_co_borr(loan, rlcb, rl)
    #puts "creating_remote_loan_co_borr: #{loan['co_borrower']}\n#{rlcb}\n"
    rlcb.first_name = loan['co_borrower']['first_name']
    rlcb.last_name = loan['co_borrower']['last_name']
    rlcb.dob = loan['co_borrower']['dob']
    rlcb.cell_phone = loan['co_borrower']['cell_phone']
    rlcb.home_phone = loan['co_borrower']['phone']
    rlcb.work_phone = loan['co_borrower']['work_phone']
    rlcb.email = loan['co_borrower']['email_address']
    rlcb.credit_score = loan['co_borrower']['credit_score']
    rlcb.credit_ref_number = loan['co_borrower']['credit_ref_number']
    rlcb.self_employed = loan['co_borrower']['self_employed']
    rlcb.credit_auth = loan['co_borrower']['credit_auth']
    rlcb.ssn = loan['co_borrower']['ssn'] if loan['co_borrower']['ssn'].present?

    rlcb.street1 = loan['co_borrower']['street1']
    rlcb.street2 = loan['co_borrower']['street2']
    rlcb.city = loan['co_borrower']['city']
    rlcb.state = loan['co_borrower']['state']
    rlcb.zip = loan['co_borrower']['zip']

    rlcb.co_borrower = true
    rlcb.remote_loan_id = rl.id
    begin
      rlcb.save!
      # since we just saved the object, force the read from the slave so we can guarantee we have the record
      ActiveRecordSlave.read_from_master do
        rlcb.reload
      end
    rescue => ex
      rlcb = nil
      NewRelic::Agent.notice_error(ex)
    end

    return rlcb
  end

  def self.update_remote_loan_prop(loan, rlp, rl)
    rlp.street = loan['property']['street']
    rlp.city = loan['property']['city']
    rlp.state = loan['property']['state']
    rlp.zip = loan['property']['zip']
    rlp.county = loan['property']['county']
    rlp.appraised_value = loan['property']['appraised_value']
    rlp.estimated_value = loan['property']['estimated_value']
    rlp.purchase_price = loan['property']['purchase_price']
    rlp.num_of_stories = loan['property']['num_of_stories']
    rlp.num_of_units = loan['property']['num_of_units']
    rlp.remote_loan_id = rl.id
    rlp.save!
    # since we just saved the object, force the read from the slave so we can guarantee we have the record
    ActiveRecordSlave.read_from_master do
      rlp.reload
    end

    return rlp
  end

  def self.search_encompass(los, remote_guids)
    modified_since_time = 30.days.ago.to_i
    if los.updated_at.present?
      modified_since_time = (los.updated_at - 30.hours).to_i
    end
    post_json = "{'QueryAllActiveLoans':#{remote_guids.empty?},'lstLoanGuids':null, 'ModifiedSince' : \"\\\/Date(#{modified_since_time*1000})\\\/\", 'AuthToken':'#{los.token}'}"

    resource = RestClient::Resource.new("#{los.url}", :verify_ssl => OpenSSL::SSL::VERIFY_NONE, :read_timeout => 300, :timeout => 300, :open_timeout => 300)
    response = resource.post post_json, :content_type => :json
    #response = RestClient.post "#{los.url}", post_json, :content_type => :json, :accept => :json, :timeout => 300, :open_timeout => 300, :verify_ssl => OpenSSL::SSL::VERIFY_NONE

    # Rails.logger.info response.to_s
    ActiveSupport::JSON.decode(response)
  end

  #to allow others to override
  def self.upload_doc remote_loan, encoded_file
    #puts "Encompass#upload_doc"
  end

  def self.send_documents_to_encompass(los, loan_guid, documents)
    # {"LoanGuid":"{43a644ed-0923-4629-860b-d1a17668a8b6}",
    #  "lstUnassignedFiles":
    #  [{"FileTitle":"Test.txt","FileBytesBase64":"VGhpcyBpcyBhIHNtYWxsIHRleHQgZmlsZQ=="}],
    #  "lstDocuments":[],
    #  "ConvLogEntry":{"Name":"Conv Log #3","Company":"SimpleNexus","Comments":"Another Doc Comment"},
    #  "AuthToken":"ValidAuthToken1234"}
    # hashed_json = {}
    # hashed_json << {"AuthToken" => "ValidAuthToken1234"}
    #
    # submission_json = JSON.generate(hashed_json)
    post_json = "{\"AuthToken\": \"ValidAuthToken1234\", \"LoanGuid\":\"{#{loan_guid}}\",\"lstUnassignedFiles\":["
    unassigned_file_data = ''
    documents.each_with_index do |doc, i|
      unassigned_file_data += "{\"FileTitle\": \"#{doc.name}.pdf\", \"FileBytesBase64\": \"#{Base64.strict_encode64(open(doc.image_url).read)}\""

      if i < documents.count - 1
        unassigned_file_data += '},{'
      end
    end
    post_json += "#{unassigned_file_data}}],"
    post_json += "\"ConvLogEntry\":{\"Name\":\"Documents Uploaded\",\"Company\":\"SimpleNexus\",\"Comments\":\"Documents Uploaded from SimpleNexus\"}}"
    # Rails.logger.info post_json

    response = RestClient.post "#{los.url}/SimpleNexusEncWebLink/RequestAddFiles.aspx", post_json, :content_type => :json, :accept => :json
    json = ActiveSupport::JSON.decode(response)
    if json['Status'] == 'ERROR'
      json['Message']
    else
      'OK'
    end
  end

  def self.convert_calyx_json(loan, los)
    response = {}

    # setting remote_id to be equal to the loan number plus date created to identify duplicates of the same loan.
    response['remote_id'] = "#{loan['LoanNumber']}#{get_time(loan['Loan']['DateCreated']).to_s.gsub(/\s[-\+][\d]{4}$/, '')}"
    response['loan_id'] = loan['LoanNumber']
    response['remote_loan_folder'] = loan['LoanFolder']
    response['remote_last_modified'] = get_time(loan['LastModified'])

    loan_info = loan['Loan']
    if response['loan_officer_email'].present?
      response['loan_officer_email'] = loan_info['loan_officer_email']
    elsif loan_info['LOemail'].present?
      response['loan_officer_email'] = loan_info['LOemail']
    elsif loan['F12356'].present?
      response['loan_officer_email'] = loan['F12356']
    elsif loan['F12358'].present?
      response['loan_officer_email'] = loan['F12358']
    elsif loan_info['LOID'].present?
      full_name = loan_info['LOID'].split
      #this is for calyx point (AMP) since they don't send an LO email
      sp = ServicerProfile.where("los_user_id=? OR concat(name, ' ', last_name)=?", loan_info['LOID'], loan_info['LOID'])

      if !sp.empty? && sp[0].effective_loan_los&.id == los.id
        response['loan_officer_email'] = sp[0].email
      else
        # sp = ServicerProfile.find_by_name(full_name[0])
        los.company.all_servicer_profiles_chain.each do |sprofile|
          if sprofile.name == full_name.first && sprofile.last_name == full_name.last
            response['loan_officer_email'] = sprofile.email
          end
        end
      end
    elsif loan['LoanOfficerEmail'].present?
      response['loan_officer_email'] = loan['LoanOfficerEmail']
    end

    response['loan_processor_email'] = loan_info['LPemail']
    response['remote_loan_created'] = get_time(loan_info['DateCreated'])
    response['remote_loan_opened'] = get_time(loan_info['DateFileOpened'])
    response['closing_date'] = get_time(loan_info['ClosingDate'])
    response['remote_loan_source'] = loan_info['LoanSource']
    response['remote_referral_source'] = loan_info['ReferralSource']
    response['remote_rate_locked'] = loan_info['RateIsLocked']
    response['remote_lock_expiration'] = get_time(loan_info['LockExpirationDate'])
    response['econsent_date'] = nil
    response['intent_to_proceed'] = nil
    response['closing_date'] = nil
    response['last_doc_order_date'] = nil
    response['doc_signing_date'] = nil
    response['funding_date'] = nil
    response['remote_estimated_completion'] = get_time(loan_info['DateOfEstimatedCompletion'])
    response['loan_program'] = loan_info['LoanProgram']
    response['loan_type'] = loan_info['LoanType']
    response['loan_purpose'] = loan_info['LoanPurpose']
    response['loan_term'] = loan_info['LoanTerm'].to_i
    response['interest_rate'] = loan_info['InterestRate'].to_f
    if loan_info['LoanAmount']
      response['loan_amount'] = loan_info['LoanAmount'].to_f
    elsif loan_info['LoanAmount_Total']
      response['loan_amount'] = loan_info['LoanAmount_Total'].to_f
    elsif loan_info['LoanAmount_Base']
      response['loan_amount'] = loan_info['LoanAmount_Base'].to_f
    else
      response['loan_amount'] = 0.0
    end
    response['amortization_type'] = loan_info['AmortizationType']
    response['cash_from_borrower'] = loan_info['CashFromBorrower'].to_f
    response['remote_loan_status'] = loan_info['MilestoneStatus']
    response['remote_loan_action_taken'] = loan_info['ActionTaken']

    if response['remote_loan_action_taken'].present?
      # If this is set in Encompass loans, we need to ensure the loan is inactive.
      response['remote_loan_active'] = false
    else
      response['remote_loan_active'] = true #loan_info['Active'] == 'Y'
    end

    response['remote_loan_action_taken_date'] = get_time(loan_info['ActionTakenDate'])

    loan_borrower = loan['Borrower']
    response['borrower'] = {}
    if !loan_borrower['FirstName'].blank? && !loan_borrower['LastName'].blank?
      response['borrower']['first_name'] = loan_borrower['FirstName']
      response['borrower']['middle_name'] = ''
      response['borrower']['last_name'] = loan_borrower['LastName']
      response['borrower']['marital_status'] = ''
      response['borrower']['email_address'] = loan_borrower['Email']
      response['borrower']['phone'] = loan_borrower['HomePhone']
      response['borrower']['cell_phone'] = loan_borrower['CellPhone']
      response['borrower']['work_phone'] = loan_borrower['WorkPhone']
      response['borrower']['credit_ref_number'] = loan_borrower['FICO_ReportId'] if loan_borrower['FICO_ReportId']
      response['borrower']['credit_auth'] = loan_borrower['CreditAuthDate'].present?
      response['borrower']['ssn'] = loan_borrower['SSN'] if loan_borrower['SSN'].present?
      response['borrower']['dob'] = loan_borrower['DOB']
      response['borrower']['street1'] = loan_borrower['Address']
    end

    if loan_borrower['CreditScore']
      response['borrower']['credit_score'] = loan_borrower['CreditScore']
    elsif loan_borrower['FICO_Expirian'] || loan_borrower['FICO_TransUnion'] || loan_borrower['FICO_Equifax']
      fico_expirian = loan_borrower['FICO_Expirian'].present? ? loan_borrower['FICO_Expirian'].to_i : nil
      fico_trans_union = loan_borrower['FICO_TransUnion'].present? ? loan_borrower['FICO_TransUnion'].to_i : nil
      fico_equifax = loan_borrower['FICO_Equifax'].present? ? loan_borrower['FICO_Equifax'].to_i : nil
      scores = [ fico_expirian, fico_trans_union, fico_equifax ]
      if scores
        scores.compact.sort!
        if scores.size == 3
          response['borrower']['credit_score'] = scores[1]
        elsif scores.size == 2 || scores.size == 1
          response['borrower']['credit_score'] = scores[0]
        elsif scores.size == 0
          #response['borrower']['credit_score'] = ""
        end
      end
    else
      #response['borrower']['credit_score'] = ""
    end
    # TODO when encompass sends SSN, update this
    # response['borrower']['ssn'] = loan_borrower['SSN']
    # response['borrower']['street1'] = loan_borrower['Street1']
    # response['borrower']['street2'] = loan_borrower['Street2']
    # response['borrower']['city'] = loan_borrower['City']
    # response['borrower']['state'] = loan_borrower['State']
    # response['borrower']['zip'] = loan_borrower['Zip']

    response['co_borrower'] = {}
    if loan['CoBorrower'] && loan['CoBorrower']['FirstName'].present? && loan['CoBorrower']['LastName'].present?
      loan_borrower = loan['CoBorrower']
      response['co_borrower']['first_name'] = loan_borrower['FirstName']
      response['co_borrower']['last_name'] = loan_borrower['LastName']
      response['co_borrower']['email_address'] = loan_borrower['Email']
      response['co_borrower']['phone'] = loan_borrower['HomePhone']
      response['co_borrower']['cell_phone'] = loan_borrower['CellPhone']
      response['co_borrower']['work_phone'] = loan_borrower['WorkPhone']
      response['co_borrower']['credit_score'] = loan_borrower['CreditScore']
      response['co_borrower']['credit_ref_number'] = loan_borrower['FICO_ReportId'] if loan_borrower['FICO_ReportId']
      response['co_borrower']['credit_auth'] = loan_borrower['CreditAuthDate'].present?
      response['co_borrower']['ssn'] = loan_borrower['SSN'] if loan_borrower['SSN'].present?
      response['co_borrower']['dob'] = loan_borrower['DOB']
      response['co_borrower']['street1'] = loan_borrower['Address']

      if loan_borrower['CreditScore']
        response['co_borrower']['credit_score'] = loan_borrower['CreditScore']
      elsif loan_borrower['FICO_Expirian'] || loan_borrower['FICO_TransUnion'] || loan_borrower['FICO_Equifax']
        fico_expirian = loan_borrower['FICO_Expirian'].present? ? loan_borrower['FICO_Expirian'].to_i : nil
        fico_trans_union = loan_borrower['FICO_TransUnion'].present? ? loan_borrower['FICO_TransUnion'].to_i : nil
        fico_equifax = loan_borrower['FICO_Equifax'].present? ? loan_borrower['FICO_Equifax'].to_i : nil
        scores = [ fico_expirian, fico_trans_union, fico_equifax ]
        scores.compact.sort!
        if scores.size == 3
          response['co_borrower']['credit_score'] = scores[1]
        elsif scores.size == 2 || scores.size == 1
          response['co_borrower']['credit_score'] = scores[0]
        elsif scores.size == 0
          #response['co_borrower']['credit_score'] = ""
        end
      else
        #response['co_borrower']['credit_score'] = ""
      end
      # TODO when encompass sends SSN, update this
      # response['co_borrower']['ssn'] = loan_borrower['SSN']
      # response['co_borrower']['street1'] = loan_borrower['Street1']
      # response['co_borrower']['street2'] = loan_borrower['Street2']
      # response['co_borrower']['city'] = loan_borrower['City']
      # response['co_borrower']['state'] = loan_borrower['State']
      # response['co_borrower']['zip'] = loan_borrower['Zip']
    end

    loan_property = loan['Property']
    response['property'] = {}
    if loan_property.any?
      response['property']['name'] = ''
      response['property']['street'] = loan_property['AddressStreet']
      response['property']['city'] = loan_property['AddressCity']
      response['property']['state'] = loan_property['AddressState']
      response['property']['zip'] = loan_property['AddressZip']
      response['property']['county'] = loan_property['AddressCounty']
      response['property']['appraised_value'] = loan_property['AppraisedValue'].to_f
      response['property']['estimated_value'] = loan_property['EstimatedValue'].to_f
      response['property']['purchase_price'] = loan_property['PurchasePrice'].to_f
    end

    response
  end

  def self.convert_encompass_form_json(loan)
    response = {}

    loan_info = loan['loan']
    response['remote_id'] = loan_info['los_loan_id'].gsub('{','').gsub('}','')
    response['loan_id'] = loan_info['los_loan_name']
    response['remote_loan_folder'] = loan_info['los_loan_folder']
    response['remote_last_modified'] = Time.now

    response['loan_officer_email'] = loan_info['lo_email']
    response['lo_nmls'] = loan_info['lo_nmls']
    response['los_user_id'] = loan_info['lo_id']

    response['loan_processor_email'] = loan_info['lp_email']
    response['remote_loan_created'] = get_time(loan_info['loan_created_date'])
    response['remote_loan_opened'] = Time.now
    response['closing_date'] = get_time(loan_info['closing_date'])
    response['lien_position'] = loan_info['lien_position']
    response['second_lien_amt'] = loan_info['second_lien_amt']
    response['heloc_limit'] = loan_info['heloc_limit']
    response['heloc_balance'] = loan_info['heloc_balance']
    response['aus_name'] = loan_info['aus_name']
    response['dti_low'] = loan_info['dti_low']
    response['dti_high'] = loan_info['dti_high']
    response['ltv_pct'] = loan_info['ltv']
    response['cltv_pct'] = loan_info['cltv']
    response['tltv_pct'] = loan_info['tltv']
    response['apr'] = loan_info['apr']
    response['refi_cashout_amt'] = loan_info['refi_cashout_amt']
    response['escrows_waived'] = y_n_to_boolean(loan_info['escrows_waived'])
    response['first_time_buyer'] = y_n_to_boolean(loan_info['first_time_buyer'])
    response['veteran_buyer'] = y_n_to_boolean(loan_info['veteran_buyer'])
    response['remote_loan_source'] = loan_info['loan_source']
    response['remote_referral_source'] = ''
    response['remote_rate_locked'] = loan_info['loan_is_locked']
    response['remote_lock_expiration'] = get_time(loan_info['loan_lock_expiration'])
    # response['lock_exp_buyside'] = get_time(loan_info['loan_lock_expiration_buyside'])
    response['econsent_date'] = get_time(loan_info['econsent_date'])
    response['intent_to_proceed'] = get_time(loan_info['intent_to_proceed_date'])
    response['closing_date'] = get_time(loan_info['closing_date'])
    response['last_doc_order_date'] = get_time(loan_info['last_doc_order_date'])
    response['doc_signing_date'] = get_time(loan_info['doc_signing_date'])
    response['funding_date'] = get_time(loan_info['funding_date'])
    response['remote_estimated_completion'] = ''
    response['loan_program'] = loan_info['loan_program']
    response['loan_type'] = loan_info['loan_type']
    response['property_type'] = loan_info['property_type']
    response['occupancy_status'] = loan_info['occupancy_status']
    response['loan_purpose'] = loan_info['loan_purpose']
    response['loan_term'] = loan_info['loan_term']
    response['interest_rate'] = loan_info['interest_rate'].to_f
    response['loan_amount'] = loan_info['loan_amount'] ? loan_info['loan_amount'].to_f : loan_info['loan_amount_base'].to_f
    response['loan_amount_total'] = loan_info['loan_amount'] ? loan_info['loan_amount'].to_f : loan_info['loan_amount_total'].to_f
    response['downpayment_pct'] = loan_info['downpayment_pct'].to_f
    response['downpayment_amount'] = loan_info['downpayment_amount'].to_f
    response['existing_lien_amt'] = loan_info['existing_lien_amt'].to_f #existing lien for refi
    response['proposed_monthly_mtg'] = loan_info['proposed_monthly_mtg'].to_f #existing lien for refi
    response['amortization_type'] = loan_info['amortization_type']
    response['cash_from_borrower'] = loan_info['cash_from_borrower'].to_f
    # response['present_monthly_rent'] = loan_info['present_monthly_rent'].to_f
    # response['present_monthly_mtg'] = loan_info['present_monthly_mtg'].to_f
    # response['present_monthly_otherfin'] = loan_info['present_monthly_oherfin'].to_f
    # response['present_monthly_hazins'] = loan_info['present_monthly_hazins'].to_f
    # response['present_monthly_taxes'] = loan_info['present_monthly_taxes'].to_f
    # response['present_monthly_mtgins'] = loan_info['present_monthly_mtgins'].to_f
    # response['present_monthly_hoa'] = loan_info['present_monthly_hoa'].to_f
    # response['present_monthly_other'] = loan_info['present_monthly_other'].to_f
    # response['present_monthly_total'] = loan_info['present_monthly_total'].to_f
    response['proposed_monthly_otherfin'] = loan_info['proposed_monthly_otherfin'].to_f
    response['proposed_monthly_hazins'] = loan_info['proposed_monthly_hazins'].to_f
    response['proposed_monthly_taxes'] = loan_info['proposed_monthly_taxes'].to_f
    response['proposed_monthly_mtgins'] = loan_info['proposed_monthly_mtgins'].to_f
    response['proposed_monthly_hoa'] = loan_info['proposed_monthly_hoa'].to_f
    response['proposed_monthly_other'] = loan_info['proposed_monthly_other'].to_f
    response['total_monthly_pmt'] = loan_info['proposed_monthly_total'].to_f
    response['p_and_i_payment'] = loan_info['monthly_payment_PI'].to_f
    response['payment_frequency'] = loan_info['payment_frequency'].to_f
    response['total_payment_le'] = loan_info['LE_total_payment'].to_f
    response['total_payment_cd'] = loan_info['CD_total_payment'].to_f
    response['initial_le_sent'] = get_time(loan_info['track_initial_le_sent'])
    response['initial_le_received'] = get_time(loan_info['track_initial_le_received'])
    response['revised_le_sent'] = get_time(loan_info['track_revised_le_sent'])
    response['revised_le_received'] = get_time(loan_info['track_revised_le_received'])
    response['initial_cd_sent'] = get_time(loan_info['track_initial_cd_sent'])
    response['initial_cd_received'] = get_time(loan_info['track_initial_cd_received'])
    response['revised_cd_sent'] = get_time(loan_info['track_revised_cd_sent'])
    response['revised_cd_received'] = get_time(loan_info['track_revised_cd_received'])
    response['approved_date'] = get_time(loan_info['uw_approval_date'])
    # TODO: continue from HERE

    if loan_info['track_appraisal_ordered_uw']
      response['appraisal_ordered_date'] = get_time(loan_info['track_appraisal_ordered_uw'])
    else
      response['appraisal_ordered_date'] = get_time(loan_info['track_appraisal_ordered_doc'])
    end
    if loan_info['track_appraisal_received_uw']
      response['appraisal_received_date'] = get_time(loan_info['track_appraisal_received_uw'])
    else
      response['appraisal_received_date'] = get_time(loan_info['track_appraisal_received_doc'])
    end
    if loan_info['track_appraisal_reviewed_uw']
      response['appraisal_reviewed_date'] = get_time(loan_info['track_appraisal_reviewed_uw'])
    else
      response['appraisal_reviewed_date'] = get_time(loan_info['track_appraisal_reviewed_doc'])
    end


    response['remote_loan_status'] = loan_info['milestone_last_completed']
    response['remote_loan_action_taken'] = loan_info['loan_action_taken']
    response['remote_loan_action_taken_date'] = get_time(loan_info['loan_action_date'])
    response['remote_loan_active'] = loan_info['remove_from_lo_app'] && loan_info['remove_from_lo_app'] == true ? false : true
    if loan_info['lstAdditionalFields']
      loan_info['lstAdditionalFields'].each do |adlField|
        field_value = adlField['v1']
        field_id = adlField['id']
        if field_id == '2353'
          response['appraisal_received_date'] = get_date_with_time( get_time( field_value ) )
        elsif field_id == 'Document.DateReceived.Appraisal'
          response['appraisal_received_date'] = get_date_with_time( get_time( field_value ) )
        elsif field_id == '2352'
          response['appraisal_ordered_date'] = get_date_with_time( get_time( field_value ) )
        elsif field_id == 'Document.DateOrdered.Appraisal'
          # TODO confirm this field_id?
          response['appraisal_ordered_date'] = get_date_with_time( get_time( field_value ) )
        #Virginia Credit Union
        elsif field_id == 'CX.SRV.APPRAISAL.ORDER'
          response['appraisal_ordered_date'] = get_date_with_time( get_time( field_value ) )
        elsif field_id == 'CX.SRV.APPRAISAL.RECEIVED'
          response['appraisal_received_date'] = get_date_with_time( get_time( field_value ) )
        elsif field_id == '3977'
          response['closing_disclosure_sent_date'] = get_date_with_time( get_time( field_value ) )
        #USA mortgage
        elsif field_id == 'CX.APPORDERED'
          response['appraisal_ordered_date'] = get_date_with_time( get_time( field_value ) )
        elsif field_id == '2360' #todo: track_appraisal_reviewed_uw
          response['appraisal_reviewed_date'] = get_date_with_time( get_time( field_value ) )
        elsif field_id == 'Document.DateReviewed.Appraisal' #todo: track_appraisal_reviewed_doc
          response['appraisal_reviewed_date'] = get_date_with_time( get_time( field_value ) )
        # TODO: ADD intent_to_proceed_letter_sent_date
        elsif field_id == '2301' #todo: uw_approval_date
          response['approved_date'] = get_time(field_value)
        elsif field_id == '912' # todo: proposed_monthly_total
          response['total_monthly_pmt'] = field_value
        elsif field_id == '799' # todo: apr
          response['apr'] = field_value
        elsif field_id == '1109' # todo: replaced by loan_amount_base
          response['loan_amount_base'] = field_value
        elsif field_id == '142'
          response['cash_to_close'] = field_value
        elsif field_id == '169'
          response['estimated_cash_to_close'] = field_value
        elsif field_id == '742' # todo: dti_high
          response['dti_high'] = field_value
        elsif field_id == '353' # todo: replaced by ltv_pct
          response['ltv_pct'] = field_value
        elsif field_id == '3197' # todo: replaced by intent_to_proceed_date
          response['intent_to_proceed'] = field_value
        elsif field_id == 'VASUMM.X23' #todo: replaced by borrower.credit_score
          response['representative_fico'] = field_value
        elsif field_id == '5' #todo: monthly_payment_PI
          response['p_and_i_payment'] = field_value
        elsif field_id == 'Document.ExpirationDate.CREDIT REPORT'
          response['credit_report_expiration_date'] = field_value
        elsif field_id == 'CX.PREQUALWCRED'
            response['prequal_allowed'] = field_value
        elsif field_id == 'CX.PREAPPROVAL'
          response['preapproval_allowed'] = field_value
        elsif field_id == 'CX.PA.3'
          response['preapproval_allowed'] = field_value
        elsif field_id == 'CX.UWNOTES.PREAPP.APPROVED'
            response['preapproval_allowed'] = field_value
        elsif field_id == 'CX.AZPQ.4'
          response['relying_on_sale_or_lease_to_qualify_yes'] = field_value
        elsif field_id == 'CX.AZPQ.5'
          response['relying_on_sale_or_lease_to_qualify_no'] = field_value
        elsif field_id == 'CX.AZPQ.6'
          response['relying_on_seller_concessions_yes'] = field_value
        elsif field_id == 'CX.AZPQ.7'
          response['relying_on_seller_concessions_no'] = field_value
        elsif field_id == 'CX.AZPQ.170'
          response['relying_on_down_payment_assistance_yes'] = field_value
        elsif field_id == 'CX.AZPQ.171'
          response['relying_on_down_payment_assistance_no'] = field_value
        elsif field_id == 'CX.AZPQ.21'
          response['lender_has_provided_hud_form_for_fha_loans_yes'] = field_value
        elsif field_id == 'CX.AZPQ.22'
          response['lender_has_provided_hud_form_for_fha_loans_no'] = field_value
        elsif field_id == 'CX.AZPQ.23'
          response['lender_has_provided_hud_form_for_fha_loans_na'] = field_value
        elsif field_id == 'CX.AZPQ.24'
          response['verbal_discussion_of_income_assets_and_debts_yes'] = field_value
        elsif field_id == 'CX.AZPQ.25'
          response['verbal_discussion_of_income_assets_and_debts_no'] = field_value
        elsif field_id == 'CX.AZPQ.26'
          response['verbal_discussion_of_income_assets_and_debts_na'] = field_value
        elsif field_id == 'CX.AZPQ.27'
          response['lender_has_obtained_tri_merged_residential_credit_report_yes'] = field_value
        elsif field_id == 'CX.AZPQ.28'
          response['lender_has_obtained_tri_merged_residential_credit_report_no'] = field_value
        elsif field_id == 'CX.AZPQ.29'
          response['lender_has_obtained_tri_merged_residential_credit_report_na'] = field_value
        elsif field_id == 'CX.AZPQ.30'
          response['lender_has_received_paystubs_yes'] = field_value
        elsif field_id == 'CX.AZPQ.31'
          response['lender_has_received_paystubs_no'] = field_value
        elsif field_id == 'CX.AZPQ.32'
          response['lender_has_received_paystubs_na'] = field_value
        elsif field_id == 'CX.AZPQ.33'
          response['lender_has_received_w2s_yes'] = field_value
        elsif field_id == 'CX.AZPQ.34'
          response['lender_has_received_w2s_no'] = field_value
        elsif field_id == 'CX.AZPQ.35'
          response['lender_has_received_w2s_na'] = field_value
        elsif field_id == 'CX.AZPQ.36'
          response['lender_has_received_personal_tax_returns_yes'] = field_value
        elsif field_id == 'CX.AZPQ.37'
          response['lender_has_received_personal_tax_returns_no'] = field_value
        elsif field_id == 'CX.AZPQ.38'
          response['lender_has_received_personal_tax_returns_na'] = field_value
        elsif field_id == 'CX.AZPQ.39'
          response['lender_has_received_corporate_tax_returns_yes'] = field_value
        elsif field_id == 'CX.AZPQ.40'
          response['lender_has_received_corporate_tax_returns_no'] = field_value
        elsif field_id == 'CX.AZPQ.41'
          response['lender_has_received_corporate_tax_returns_na'] = field_value
        elsif field_id == 'CX.AZPQ.42'
          response['lender_has_received_down_payment_reserves_documentation_yes'] = field_value
        elsif field_id == 'CX.AZPQ.43'
          response['lender_has_received_down_payment_reserves_documentation_no'] = field_value
        elsif field_id == 'CX.AZPQ.44'
          response['lender_has_received_down_payment_reserves_documentation_na'] = field_value
        elsif field_id == 'CX.AZPQ.45'
          response['lender_has_received_gift_documentation_yes'] = field_value
        elsif field_id == 'CX.AZPQ.46'
          response['lender_has_received_gift_documentation_no'] = field_value
        elsif field_id == 'CX.AZPQ.47'
          response['lender_has_received_gift_documentation_na'] = field_value
        elsif field_id == 'CX.AZPQ.48'
          response['lender_has_received_credit_liability_documentation_yes'] = field_value
        elsif field_id == 'CX.AZPQ.49'
          response['lender_has_received_credit_liability_documentation_no'] = field_value
        elsif field_id == 'CX.AZPQ.50'
          response['lender_has_received_credit_liability_documentation_na'] = field_value
        elsif field_id == 'CX.AZPQ.27COMMENTS'
          response['additional_comments'] = field_value
        elsif field_id == 'CX.AZPQ.EXPDATE'
          response['expiration_date'] = get_date_without_time(field_value                                                                   )
        end
      end
    end

    loan_borrower = loan['borrower']
    response['borrower'] = {}
    response['borrower']['app_user_id'] = loan_borrower['app_user_id'] ? loan_borrower['app_user_id'] : loan['app_user_id']
    response['borrower']['first_name'] = loan_borrower['first_name']
    response['borrower']['middle_name'] = loan_borrower['middle_name']
    response['borrower']['suffix'] = loan_borrower['name_suffix']
    response['borrower']['marital_status'] = loan_borrower['marital_status']
    response['borrower']['last_name'] = loan_borrower['last_name']
    response['borrower']['email_address'] = loan_borrower['email_address'] ? loan_borrower['email_address'] : loan_borrower['home_email']
    response['borrower']['phone'] = loan_borrower['home_phone']
    response['borrower']['cell_phone'] = loan_borrower['cell_phone']
    response['borrower']['work_phone'] = loan_borrower['work_phone']
    response['borrower']['credit_score'] = loan_borrower['credit_score']
    response['borrower']['ssn'] = loan_borrower['ssn']

    if loan_borrower['present_address']
      response['borrower']['street1'] = loan_borrower['present_address']['street']
      response['borrower']['city'] = loan_borrower['present_address']['city']
      response['borrower']['state'] = loan_borrower['present_address']['state']
      response['borrower']['zip'] = loan_borrower['present_address']['zip']
    else
      response['borrower']['street1'] = loan_borrower['present_street1']
      response['borrower']['street2'] = loan_borrower['present_street2']
      response['borrower']['city'] = loan_borrower['present_city']
      response['borrower']['state'] = loan_borrower['present_state']
      response['borrower']['zip'] = loan_borrower['present_zip']
    end

    response['borrower']['dob'] = loan_borrower['dob']

    if loan_borrower['credit']
      response['borrower']['credit_ref_number'] = loan_borrower['credit']['ref_number']
      response['borrower']['credit_auth'] = loan_borrower['credit']['authorized']
      response['borrower']['credit_decision_score'] = loan_borrower['credit']['decision_score']
      response['borrower']['credit_auth_method'] = loan_borrower['credit']['auth_method']
    else
      response['borrower']['credit_ref_number'] = loan_borrower['credit_ref_number']
      response['borrower']['credit_auth'] = y_n_to_boolean(loan_borrower['credit_auth'])
    end

    if response['borrower']['econsent']
      response['borrower']['econsent_status'] = loan_borrower['econsent']['accepted']
      response['borrower']['econsent_date'] = get_time(loan_borrower['econsent']['consent_date'])
      response['borrower']['econsent_ip_address'] = get_time(loan_borrower['econsent']['ip_address'])
    end

    # response['borrower']['self_employed'] = y_n_to_boolean(loan_borrower['self_employed'])

    loan_borrower = loan['co_borrower']
    response['co_borrower'] = {}
    # encompass is sending throubh blank coborrower information... when there isn't really a coborrower. So lets say that we at least need a name to continue
    if loan_borrower && !loan['co_borrower']['first_name'].blank? && !loan['co_borrower']['last_name'].blank?
      response['co_borrower']['app_user_id'] = loan_borrower['app_user_id'] ? loan_borrower['app_user_id'] : loan['app_user_id']
      response['co_borrower']['first_name'] = loan_borrower['first_name']
      response['co_borrower']['last_name'] = loan_borrower['last_name']
      response['co_borrower']['middle_name'] = loan_borrower['middle_name']
      response['co_borrower']['suffix'] = loan_borrower['name_suffix']
      response['co_borrower']['marital_status'] = loan_borrower['marital_status']
      response['co_borrower']['email_address'] = loan_borrower['email_address'] ? loan_borrower['email_address'] : loan_borrower['home_email']
      response['co_borrower']['phone'] = loan_borrower['home_phone']
      response['co_borrower']['cell_phone'] = loan_borrower['cell_phone']
      response['co_borrower']['work_phone'] = loan_borrower['work_phone']
      response['co_borrower']['credit_score'] = loan_borrower['credit_score']
      response['co_borrower']['ssn'] = loan_borrower['ssn']
      if loan_borrower['present_address']
        response['co_borrower']['street1'] = loan_borrower['present_address']['street']
        response['co_borrower']['city'] = loan_borrower['present_address']['city']
        response['co_borrower']['state'] = loan_borrower['present_address']['state']
        response['co_borrower']['zip'] = loan_borrower['present_address']['zip']
      else
        response['co_borrower']['street1'] = loan_borrower['present_street1']
        response['co_borrower']['street2'] = loan_borrower['present_street2']
        response['co_borrower']['city'] = loan_borrower['present_city']
        response['co_borrower']['state'] = loan_borrower['present_state']
        response['co_borrower']['zip'] = loan_borrower['present_zip']
      end

      response['co_borrower']['dob'] = loan_borrower['dob']

      if loan_borrower['credit']
        response['co_borrower']['credit_ref_number'] = loan_borrower['credit']['ref_number']
        response['co_borrower']['credit_auth'] = loan_borrower['credit']['authorized']
        response['co_borrower']['credit_decision_score'] = loan_borrower['credit']['decision_score']
        response['co_borrower']['credit_auth_method'] = loan_borrower['credit']['auth_method']
      else
        response['co_borrower']['credit_ref_number'] = loan_borrower['credit_ref_number']
        response['co_borrower']['credit_auth'] = y_n_to_boolean(loan_borrower['credit_auth'])
      end

      if response['borrower']['econsent']
        response['co_borrower']['econsent_status'] = loan_borrower['econsent']['accepted']
        response['co_borrower']['econsent_date'] = get_time(loan_borrower['econsent']['consent_date'])
        response['co_borrower']['econsent_ip_address'] = get_time(loan_borrower['econsent']['ip_address'])
      end

      # response['borrower']['self_employed'] = y_n_to_boolean(loan_borrower['self_employed'])
    end

    buyer_agent = loan['loan']['BuyerAgent']
    response['buyer_agent'] = {}
    if buyer_agent
      response['buyer_agent']['partner_type'] = buyer_agent['buyer_agent']
      response['buyer_agent']['name'] = buyer_agent['agent_name']
      response['buyer_agent']['email'] = buyer_agent['agent_email']
      response['buyer_agent']['phone'] = buyer_agent['agent_phone']
      response['buyer_agent']['cell_phone'] = buyer_agent['agent_cell']
      response['buyer_agent']['fax'] = buyer_agent['agent_fax']
      response['buyer_agent']['agent_license'] = buyer_agent['agent_license']
      response['buyer_agent']['company_name'] = buyer_agent['company_name']
      response['buyer_agent']['street'] = buyer_agent['company_street']
      response['buyer_agent']['city'] = buyer_agent['company_city']
      response['buyer_agent']['state'] = buyer_agent['company_state']
      response['buyer_agent']['zip'] = buyer_agent['company_zip']
      response['buyer_agent']['company_license'] = buyer_agent['company_license']
    end

    seller_agent = loan['loan']['SellerAgent']
    response['seller_agent'] = {}
    # encompass is sending throubh blank coborrower information... when there isn't really a coborrower. So lets say that we at least need a name to continue
    if seller_agent
      response['seller_agent']['partner_type'] = seller_agent['seller_agent']
      response['seller_agent']['name'] = seller_agent['agent_name']
      response['seller_agent']['email'] = seller_agent['agent_email']
      response['seller_agent']['phone'] = seller_agent['agent_phone']
      response['seller_agent']['cell_phone'] = seller_agent['agent_cell']
      response['seller_agent']['fax'] = seller_agent['agent_fax']
      response['seller_agent']['agent_license'] = seller_agent['agent_license']
      response['seller_agent']['company_name'] = seller_agent['company_name']
      response['seller_agent']['street'] = seller_agent['company_street']
      response['seller_agent']['city'] = seller_agent['company_city']
      response['seller_agent']['state'] = seller_agent['company_state']
      response['seller_agent']['zip'] = seller_agent['company_zip']
      response['seller_agent']['company_license'] = seller_agent['company_license']
    end

    settlement_agent = loan['loan']['SettlementAgent']
    response['settlement_agent'] = {}
    # encompass is sending throubh blank coborrower information... when there isn't really a coborrower. So lets say that we at least need a name to continue
    if settlement_agent
      response['settlement_agent']['partner_type'] = seller_agent['settlement_agent']
      response['settlement_agent']['name'] = seller_agent['agent_name']
      response['settlement_agent']['email'] = seller_agent['agent_email']
      response['settlement_agent']['phone'] = seller_agent['agent_phone']
      response['settlement_agent']['cell_phone'] = seller_agent['agent_cell']
      response['settlement_agent']['fax'] = seller_agent['agent_fax']
      response['settlement_agent']['agent_license'] = seller_agent['agent_license']
      response['settlement_agent']['company_name'] = seller_agent['company_name']
      response['settlement_agent']['street'] = seller_agent['company_street']
      response['settlement_agent']['city'] = seller_agent['company_city']
      response['settlement_agent']['state'] = seller_agent['company_state']
      response['settlement_agent']['zip'] = seller_agent['company_zip']
      response['settlement_agent']['company_license'] = seller_agent['company_license']
    end

    loan_property = loan['property']
    response['property'] = {}
    if loan_property.any?
      response['property']['name'] = ''
      response['property']['street'] = loan_property['street']
      response['property']['city'] = loan_property['city']
      response['property']['state'] = loan_property['state']
      response['property']['zip'] = loan_property['zip']
      response['property']['county'] = loan_property['county']
      response['property']['appraised_value'] = loan_property['appraised_value'].to_f
      response['property']['estimated_value'] = loan_property['estimated_value'].to_f
      response['property']['purchase_price'] = loan_property['purchase_price'].to_f
      response['property']['num_of_units'] = loan_property['num_of_units']
      response['property']['num_of_stories'] = loan_property['num_of_stories']
    end

    response['alerts'] = []
    if loan['alerts'] && loan['alerts']['data']
      alert_arr = loan['alerts']['data']
      alert_arr.each do |alert|
        response['alerts'] << alert
      end
    end

    response['milestone_events'] = []
    if loan['loan']['milestone_events']
      events = loan['loan']['milestone_events']
      events.each do |event|
        ms_event = {}
        ms_event['name'] = event['name']
        ms_event['date'] = event['date']
        ms_event['completed'] = event['completed']
        ms_event['associate_name'] = event['associate_name']
        ms_event['associate_email'] = event['associate_email']
        ms_event['associate_phone'] = event['associate_phone']
        ms_event['associate_cell'] = event['associate_cell_email']

        response['milestone_events'] << ms_event
      end
    end

    response['los_client_version'] = loan['plugin_version']
    response['los_name'] = loan['los']

    response
  end

  def self.convert_byte_json(loan)
    response = {}
    response['borrower'] = {}
    response['co_borrower'] = {}
    response['buyer_agent'] = {}
    response['seller_agent'] = {}
    response['property'] = {}

    loan_fields = loan['lstFields']
    loan_fields.each do |field|
      case field['FullFieldID']
        when 'FileData.FileName'
          response['loan_id'] = field['Value']
        when 'Loan.LoanGUID'
          response['remote_id'] = field['Value']
        when 'LO.EMail'
          response['loan_officer_email'] = field['Value']
        when 'FileData.LoanOfficerUserName'
          response['los_user_id'] = field['Value']
        when 'LP.EMail'
          response['loan_processor_email'] = field['Value']
        when 'FileData.DateCreated'
          response['remote_loan_created'] = field['Value']
        when 'Status.SchedClosingDate'
          response['closing_date'] = field['Value']
        when 'Loan.LienPosition'
          response['lien_position'] = field['Value']
        when 'Loan.SubFiBaseLoan'
          response['second_lien_amt'] = to_currency(field['Value'])
        when 'Loan.HELOCMaxBalance'
          response['heloc_limit'] = to_currency(field['Value'])
          response['heloc_balance'] = to_currency(field['Value'])
        when 'Trans.RiskAssessmentMethod'
          response['aus_name'] = field['Value']
        when 'Loan.FirstRatio'
          response['dti_low'] = field['Value']
        when 'Loan.SecondRatio'
          response['dti_high'] = field['Value']
        when 'Loan.RefinanceCashOutAmount'
          response['refi_cashout_amt'] = to_currency(field['Value'])
        when 'FileData.WaiveEscrow'
          response['escrows_waived'] = field['Value']
          # response['escrows_waived'] = y_n_to_boolean(loan_fields['escrows_waived'])
        when 'Bor1.FirstTimeHomebuyer'
          response['first_time_buyer'] = field['Value']
          # response['first_time_buyer'] = y_n_to_boolean(loan_fields['first_time_buyer'])
        when 'Loan.LockExpirationDate'
          # todo: must ensure rate expiration is today or later.
          response['remote_rate_locked'] = field['Value'].present?
          response['remote_lock_expiration'] = get_time(field['Value'])
        when 'Loan.LoanProgramName'
          response['loan_program'] = field['Value']
        when 'Loan.MortgageType'
          response['loan_type'] = field['Value']
        when 'SubProp.PropertyType'
          response['property_type'] = field['Value']
        when 'FileData.OccupancyType'
          response['occupancy_status'] = field['Value']
        when 'Loan.LoanPurpose'
          response['loan_purpose'] = field['Value']
        when 'Loan.Term'
          response['loan_term'] = field['Value']
        when 'Loan.IntRate'
          response['interest_rate'] = field['Value']
        when 'Loan.LoanWith'
          response['loan_amount'] = to_currency(field['Value'])
        when 'Loan.AmortizationType'
          response['amortization_type'] = field['Value']
        when 'DOT.CashFromToBorrower'
          response['cash_from_borrower'] = to_currency(field['Value'])
        when 'Status.LoanStatus'
          response['remote_loan_status'] = field['EnumValue']
        when 'HMDA.ActionTaken'
          response['remote_loan_action_taken'] = field['Value']
        when 'HMDA.ActionDate'
          response['remote_loan_action_taken_date'] = get_time(field['Value'])
        when 'Status.AppraisalReceived'
          response['appraisal_received_date'] = get_time( field['Value'])
        when 'Status.AppraisalOrdered'
          response['appraisal_ordered_date'] = get_time( field['Value'])
        when 'DiscLogEntryCDInitial.DeliveryDateAndTime'
          response['closing_disclosure_sent_date'] = get_time( field['Value'])
        when 'Status.ApprovedDate'
          response['approved_date'] = get_time( field['Value'])
        when 'Loan.APR'
          response['apr'] = field['Value']
        when 'Loan.BaseLoan'
          response['loan_amount_base'] = to_currency(field['Value'])
        when 'Loan.PurPrice'
          response['purchase_price_up_to'] = to_currency(field['Value'])
        when 'DOT.CashFromToBorrower'
          response['cash_to_close'] = to_currency(field['Value'])
        when 'Loan.LTV'
          response['ltv_pct'] = field['Value']
        when 'Status.IntentToProceedDate'
          response['intent_to_proceed'] = field['Value']
        when 'Bor1.CreditScoreMedian'
          response['representative_fico'] = field['Value']
        when 'Loan.PI'
          response['p_and_i_payment'] = to_currency(field['Value'])
        when 'Bor1.FirstName'
          response['borrower']['first_name'] = field['Value']
        when 'Bor1.LastName'
          response['borrower']['last_name'] = field['Value']
        when 'Bor1.Email'
          response['borrower']['email_address'] = field['Value']
        when 'Bor1.HomePhone'
          response['borrower']['phone'] = field['Value']
        when 'Bor1.MobilePhone'
          response['borrower']['cell_phone'] = field['Value']
        when 'Bor1Emp.Phone'
          response['borrower']['work_phone'] = field['Value']
        when 'Bor1.CreditScoreMedian'
          response['borrower']['credit_score'] = field['Value']
        when 'Bor1.SSN'
          response['borrower']['ssn'] = field['Value']
        when 'Bor1.MailingStreet'
          response['borrower']['street1'] = field['Value']
        when 'Bor1.MailingCity'
          response['borrower']['city'] = field['Value']
        when 'Bor1.MailingState'
          response['borrower']['state'] = field['Value']
        when 'Bor1.MailingZip'
          response['borrower']['zip'] = field['Value']
        when 'Bor1.DOB'
          response['borrower']['dob'] = field['Value']
        when '1003App1.CreditRefNo'
          response['borrower']['credit_ref_number'] = field['Value']
        when 'Bor1.OKToPullCredit'
          response['borrower']['credit_auth'] = field['Value']
        when 'Bor1Emp.SelfEmp'
          response['borrower']['self_employed'] = field['Value']
        when 'Bor1.FirstName'
          response['co_borrower']['first_name'] = field['Value']
        when 'Bor1.LastName'
          response['co_borrower']['last_name'] = field['Value']
        when 'Bor1.Email'
          response['co_borrower']['email_address'] = field['Value']
        when 'Bor1.HomePhone'
          response['co_borrower']['phone'] = field['Value']
        when 'Bor1.MobilePhone'
          response['co_borrower']['cell_phone'] = field['Value']
        when 'Bor1Emp.Phone'
          response['co_borrower']['work_phone'] = field['Value']
        when 'Bor1.CreditScoreMedian'
          response['co_borrower']['credit_score'] = field['Value']
        when 'Bor1.SSN'
          response['co_borrower']['ssn'] = field['Value']
        when 'Bor1.MailingStreet'
          response['co_borrower']['street1'] = field['Value']
        when 'Bor1.MailingCity'
          response['co_borrower']['city'] = field['Value']
        when 'Bor1.MailingState'
          response['co_borrower']['state'] = field['Value']
        when 'Bor1.MailingZip'
          response['co_borrower']['zip'] = field['Value']
        when 'Bor1.DOB'
          response['co_borrower']['dob'] = field['Value']
        when '1003App1.CreditRefNo'
          response['co_borrower']['credit_ref_number'] = field['Value']
        when 'Bor1.OKToPullCredit'
          response['co_borrower']['credit_auth'] = field['Value']
        when 'Bor1Emp.SelfEmp'
          response['co_borrower']['self_employed'] = field['Value']
        when 'SelAgent.FullName'
          response['buyer_agent']['partner_type'] = 'buyer_agent'
          response['buyer_agent']['name'] = field['Value']
        when 'SelAgent.EMail'
          response['buyer_agent']['email'] = field['Value']
        when 'SelAgent.WorkPhone'
          response['buyer_agent']['phone'] = field['Value']
        when 'SelAgent.MobilePhone'
          response['buyer_agent']['cell_phone'] = field['Value']
        when 'SelAgent.LicenseNo'
          response['buyer_agent']['agent_license'] = field['Value']
        when 'SelAgent.Company'
          response['buyer_agent']['company_name'] = field['Value']
        when 'SelAgent.Street'
          response['buyer_agent']['street'] = field['Value']
        when 'SelAgent.City'
          response['buyer_agent']['city'] = field['Value']
        when 'SelAgent.State'
          response['buyer_agent']['state'] = field['Value']
        when 'SelAgent.Zip'
          response['buyer_agent']['zip'] = field['Value']
        when 'SelAgent.CompanyLicenseNo'
          response['buyer_agent']['company_license'] = field['Value']
        when 'ListAgent.FullName'
          response['seller_agent']['partner_type'] = 'seller_agent'
          response['seller_agent']['name'] = field['Value']
        when 'ListAgent.EMail'
          response['seller_agent']['email'] = field['Value']
        when 'ListAgent.WorkPhone'
          response['seller_agent']['phone'] = field['Value']
        when 'ListAgent.MobilePhone'
          response['seller_agent']['cell_phone'] = field['Value']
        when 'ListAgent.LicenseNo'
          response['seller_agent']['agent_license'] = field['Value']
        when 'ListAgent.Company'
          response['seller_agent']['company_name'] = field['Value']
        when 'ListAgent.Street'
          response['seller_agent']['street'] = field['Value']
        when 'ListAgent.City'
          response['seller_agent']['city'] = field['Value']
        when 'ListAgent.State'
          response['seller_agent']['state'] = field['Value']
        when 'ListAgent.Zip'
          response['seller_agent']['zip'] = field['Value']
        when 'ListAgent.CompanyLicenseNo'
          response['seller_agent']['company_license'] = field['Value']
        when 'SubProp.Street'
          response['property']['street'] = field['Value']
        when 'SubProp.City'
          response['property']['city'] = field['Value']
        when 'SubProp.State'
          response['property']['state'] = field['Value']
        when 'SubProp.Zip'
          response['property']['zip'] = field['Value']
        when 'SubProp.County'
          response['property']['county'] = field['Value']
        when 'SubProp.AppraisedValue'
          response['property']['appraised_value'] = to_currency(field['Value'])
        when 'SubProp.AssessedValue'
          response['property']['estimated_value'] = to_currency(field['Value'])
        when 'Loan.PurPrice'
          response['property']['purchase_price'] = to_currency(field['Value'])
        when 'SubProp.NoUnits'
          response['property']['num_of_units'] = field['Value']
        when 'SubProp.Stories'
          response['property']['num_of_stories'] = field['Value']
        when ''
          response[''] = field['Value']
      end
    end

    response['remote_last_modified'] = Time.now
    response['remote_loan_opened'] = Time.now
    response['remote_estimated_completion'] = ''

    response['los_client_version'] = loan['plugin_version']
    response['los_name'] = 'byte'

    response
  end

  def self.convert_mb_json(loan)
    response = {}

    loan_info = loan['loan']
    response['remote_id'] = loan_info['los_loan_id'].gsub('{','').gsub('}','')
    response['loan_id'] = loan_info['los_loan_name']
    response['remote_loan_folder'] = loan_info['los_loan_folder'] # not coming through
    response['remote_last_modified'] = loan_info['loan_last_saved']

    response['loan_officer_email'] = loan_info['lo_email']
    response['lo_nmls'] = loan_info['lo_nmls']
    response['los_user_id'] = loan_info['lo_id']

    response['loan_processor_email'] = loan_info['lp_email']
    response['remote_loan_created'] = get_time(loan_info['loan_created_date'])
    response['remote_loan_opened'] = Time.now
    response['closing_date'] = get_time(loan_info['closing_date'])
    response['remote_loan_source'] = loan_info['loan_source']
    response['remote_referral_source'] = '' #not coming through.
    # todo: see if there is a lock date, and if the date has not passed.
    # We could probably put this logic somewhere else.
    response['remote_rate_locked'] = loan_info['loan_is_locked']
    response['remote_lock_expiration'] = get_time(loan_info['loan_lock_date'])
    response['remote_estimated_completion'] = ''
    response['loan_program'] = loan_info['loan_program']
    response['loan_type'] = loan_info['loan_type']
    response['property_type'] = loan_info['property_type'] # not coming through
    response['occupancy_status'] = loan_info['occupancy_status'] # not coming through
    response['loan_purpose'] = loan_info['loan_purpose']
    response['loan_term'] = loan_info['loan_term']
    response['interest_rate'] = loan_info['interest_rate'].to_f
    response['loan_amount'] = loan_info['loan_amount'].to_f
    response['amortization_type'] = loan_info['amortization_type']
    response['cash_from_borrower'] = loan_info['cash_from_borrower'].to_f
    response['remote_loan_status'] = loan_info['milestone_last_completed']
    response['remote_loan_action_taken'] = ''; #loan_info['loan_action_taken']
    response['remote_loan_action_taken_date'] = get_time(loan_info['loan_action_date'])
    response['remote_loan_active'] = true #loan_info['Active'] == 'Y'

    loan_borrower = loan['borrower']
    response['borrower'] = {}
    response['borrower']['app_user_id'] = loan_borrower['app_user_id'] ? loan_borrower['app_user_id'] : loan['app_user_id']
    response['borrower']['first_name'] = loan_borrower['first_name']
    response['borrower']['last_name'] = loan_borrower['last_name']
    response['borrower']['email_address'] = loan_borrower['email_address'] ? loan_borrower['email_address'] : loan_borrower['home_email']
    response['borrower']['phone'] = loan_borrower['home_phone']
    response['borrower']['cell_phone'] = loan_borrower['cell_phone']
    response['borrower']['work_phone'] = loan_borrower['work_phone']
    response['borrower']['credit_score'] = loan_borrower['credit_score']
    response['borrower']['ssn'] = loan_borrower['ssn']
    response['borrower']['street1'] = loan_borrower['present_street1']
    response['borrower']['street2'] = loan_borrower['present_street2']
    response['borrower']['city'] = loan_borrower['present_city']
    response['borrower']['state'] = loan_borrower['present_state']
    response['borrower']['zip'] = loan_borrower['present_zip']
    response['borrower']['dob'] = loan_borrower['dob']
    response['borrower']['credit_ref_number'] = loan_borrower['credit_ref_number']
    response['borrower']['credit_auth'] = loan_borrower['credit_auth']
    response['borrower']['self_employed'] = loan_borrower['self_employed']

    loan_borrower = loan['co_borrower']
    response['co_borrower'] = {}
    # encompass is sending throubh blank coborrower information... when there isn't really a coborrower. So lets say that we at least need a name to continue
    if loan_borrower && !loan['co_borrower']['first_name'].blank? && !loan['co_borrower']['last_name'].blank?
      response['co_borrower']['app_user_id'] = loan_borrower['app_user_id'] ? loan_borrower['app_user_id'] : loan['app_user_id']
      response['co_borrower']['first_name'] = loan_borrower['first_name']
      response['co_borrower']['last_name'] = loan_borrower['last_name']
      response['co_borrower']['email_address'] = loan_borrower['email_address'] ? loan_borrower['email_address'] : loan_borrower['home_email']
      response['co_borrower']['phone'] = loan_borrower['home_phone']
      response['co_borrower']['cell_phone'] = loan_borrower['cell_phone']
      response['co_borrower']['work_phone'] = loan_borrower['work_phone']
      response['co_borrower']['credit_score'] = loan_borrower['credit_score']
      response['co_borrower']['ssn'] = loan_borrower['ssn']
      response['co_borrower']['street1'] = loan_borrower['present_street1']
      response['co_borrower']['street2'] = loan_borrower['present_street2']
      response['co_borrower']['city'] = loan_borrower['present_city']
      response['co_borrower']['state'] = loan_borrower['present_state']
      response['co_borrower']['zip'] = loan_borrower['present_zip']
      response['co_borrower']['dob'] = loan_borrower['dob']
      response['co_borrower']['credit_ref_number'] = loan_borrower['credit_ref_number']
      response['co_borrower']['credit_auth'] = loan_borrower['credit_auth']
      response['co_borrower']['self_employed'] = loan_borrower['self_employed']
    end

    loan_property = loan['property']
    response['property'] = {}
    if loan_property['street'].present?
      response['property']['name'] = ''
      response['property']['street'] = loan_property['street']
      response['property']['city'] = loan_property['city']
      response['property']['state'] = loan_property['state']
      response['property']['zip'] = loan_property['zip']
      response['property']['county'] = loan_property['county']
      response['property']['appraised_value'] = loan_property['appraised_value'].to_f
      response['property']['estimated_value'] = loan_property['estimated_value'].to_f
      response['property']['purchase_price'] = loan_property['purchase_price'].to_f
      response['property']['num_of_stories'] = loan_property['num_of_stories']
      response['property']['num_of_units'] = loan_property['num_of_units']
    end

    response['alerts'] = []
    if loan['alerts'] && loan['alerts']['data']
      alert_arr = loan['alerts']['data']
      alert_arr.each do |alert|
        response['alerts'] << alert
      end
    end

    response
  end

  def self.convert_sftp_csv(loan)
    response = {}

    response['remote_id'] = loan['LoanID'].strip.gsub(/\"/, '').to_i
    response['loan_id'] = loan['LoanID'].strip.gsub(/\"/, '').to_i
    # response['loan_id'] = loan['LenderLoanNumber'].strip
    response['remote_loan_folder'] = ''
    response['remote_last_modified'] = Time.now.to_s
    response['loan_officer_email'] = loan['LoanOfficerEmail']&.strip&.downcase

    response['remote_loan_created'] = EncompassBrokerPuller::get_sftp_time(loan['ApplicationDate'])
    response['remote_loan_opened'] = EncompassBrokerPuller::get_sftp_time(loan['ApplicationDate'])
    response['closing_date'] = EncompassBrokerPuller::get_sftp_time(loan['EstimatedClosingDate'])
    response['remote_loan_source'] = ''
    response['remote_referral_source'] = ''
    response['remote_rate_locked'] = loan['LockExpDate'].strip.present? ? 1 : 0 if loan['LockExpDate'].present?
    response['remote_lock_expiration'] = EncompassBrokerPuller::get_sftp_time(loan['LockExpDate']) if loan['LockExpDate'].present?
    response['econsent_date'] = nil
    response['intent_to_proceed'] = nil
    response['closing_date'] = nil
    response['last_doc_order_date'] = nil
    response['doc_signing_date'] = nil
    response['funding_date'] = nil
    response['remote_estimated_completion'] = EncompassBrokerPuller::get_sftp_time(loan['FundedDate'])
    response['loan_program'] = loan['LoanProgram'].strip if loan['LoanProgram'].present?
    response['loan_type'] = loan['LoanType'].strip if loan['LoanType'].present?
    response['loan_purpose'] = loan['LoanPurpose'].strip if loan['LoanPurpose'].present?
    response['loan_term'] = loan['LoanTerm'].strip if loan['LoanTerm'].present?
    response['interest_rate'] = loan['LoanInterestRate'].strip.to_f if loan['LoanInterestRate'].present?
    response['loan_amount'] = loan['LoanAmount'].strip.to_f if loan['LoanAmount'].present?
    response['amortization_type'] = loan['LoanAmortization'].strip if loan['LoanAmortization'].present?
    response['loan_amount_total'] = loan['LoanAmount'].strip.to_f if loan['LoanAmount'].present?
    response['downpayment_pct'] = 0
    response['cash_from_borrower'] = 0
    response['downpayment_amount'] = 0
    response['existing_lien_amt'] = 0
    response['proposed_monthly_mtg'] = 0
    response['proposed_monthly_otherfin'] = 0
    response['proposed_monthly_hazins'] = 0
    response['proposed_monthly_taxes'] = 0
    response['proposed_monthly_mtgins'] = 0
    response['proposed_monthly_hoa'] = 0
    response['proposed_monthly_other'] = 0
    response['total_monthly_pmt'] = 0
    response['p_and_i_payment'] = 0
    response['payment_frequency'] = 0
    response['total_payment_le'] = 0
    response['total_payment_cd'] = 0
    response['initial_le_sent'] = nil
    response['initial_le_received'] = nil
    response['revised_le_sent'] = nil
    response['revised_le_received'] = nil
    response['initial_cd_sent'] = nil
    response['initial_cd_received'] = nil
    response['revised_cd_sent'] = nil
    response['revised_cd_received'] = nil
    response['approved_date'] = nil

    response['remote_loan_status'] = loan['LoanStatus'].strip if loan['LoanStatus'].present?
    approval_status = loan['ApprovalStatus'].strip if loan['ApprovalStatus'].present?

    response['remote_loan_active'] = loan['LoanStatus'].present? && loan['LoanStatus'].strip != 'Withdrawn' && loan['LoanStatus'].strip != 'Denied' && loan['LoanStatus'].strip != 'Cancelled'

    if response['remote_loan_active']
      application_date = EncompassBrokerPuller::get_sftp_time(loan['ApplicationDate'].strip) if loan['ApplicationDate'].present?
      underwriting_date = EncompassBrokerPuller::get_sftp_time(loan['LoanSubmittedToUnderwriting'].strip) if loan['LoanSubmittedToUnderwriting'].present?
      appraisal_ordered_date = EncompassBrokerPuller::get_sftp_time(loan['AppraisalOrderDate'].strip) if loan['AppraisalOrderDate'].present?
      clear_to_close_date = EncompassBrokerPuller::get_sftp_time(loan['UWApprovedDate'].strip) if loan['UWApprovedDate'].present?
      funded_date = EncompassBrokerPuller::get_sftp_time(loan['FundedDate'].strip) if loan['FundedDate'].present?
      closing_disclosure_sent_date = EncompassBrokerPuller::get_sftp_time(loan['ClosingDisclosureSentDate'].strip) if loan['ClosingDisclosureSentDate'].present?
      if loan['LoanStatus'].casecmp("10 day letter") == 0
        intent_to_proceed_letter_sent_date = Time.now.to_s
      elsif loan['LoanStatus'].casecmp("appraisal received") == 0
        appraisal_received_date = Time.now.to_s
      elsif loan['LoanStatus'].casecmp("appraisal review complete") == 0
        appraisal_reviewed_date = Time.now.to_s
      end
      if loan['ApprovalStatus'].present? && (loan['ApprovalStatus'].casecmp('approved') == 0)
        approved_date = Time.now.to_s
      end

      response['appraisal_ordered_date'] = get_date_with_time( appraisal_ordered_date ) if appraisal_ordered_date.present?
      response['appraisal_received_date'] = get_date_with_time( appraisal_received_date ) if appraisal_received_date.present?
      response['appraisal_reviewed_date'] = get_date_with_time( appraisal_reviewed_date ) if appraisal_reviewed_date.present?
      response['intent_to_proceed_letter_sent_date'] = get_date_with_time( intent_to_proceed_letter_sent_date ) if intent_to_proceed_letter_sent_date.present?
      response['approved_date'] = approved_date if approved_date.present?
      response['closing_disclosure_sent_date'] = get_date_with_time( closing_disclosure_sent_date ) if closing_disclosure_sent_date.present?

      # if funded_date
      #   response['remote_loan_status'] = 'Funded'
      # elsif clear_to_close_date
      #   response['remote_loan_status'] = 'Clear to Close'
      # elsif underwriting_date
      #   response['remote_loan_status'] = 'Submitted to Underwriting'
      # elsif appraisal_ordered_date
      #   response['remote_loan_status'] = 'Appraisal Ordered'
      # elsif application_date
      #   response['remote_loan_status'] = 'Application'
      # end
    end

    response['remote_loan_action_taken'] = ''
    response['remote_loan_action_taken_date'] = ''


    response['borrower'] = {}
    if loan['FirstName'].present? && loan['LastName'].present?
      response['borrower']['first_name'] = loan['FirstName'].strip if loan['FirstName'].present?
      response['borrower']['last_name'] = loan['LastName'].strip if loan['LastName'].present?
      response['borrower']['dob'] = EncompassBrokerPuller::get_sftp_time(loan['BorrDOB'].strip) if loan['BorrDOB'].present?
      response['borrower']['email_address'] = loan['BorrEmail'].strip if loan['BorrEmail'].present?
      response['borrower']['phone'] = loan['BorrCellPhone'].strip if loan['BorrCellPhone'].present?
      response['borrower']['cell_phone'] = loan['BorrCellPhone'].strip if loan['BorrCellPhone'].present?
      response['borrower']['work_phone'] = loan['BorrCellPhone'].strip if loan['BorrCellPhone'].present?
      response['borrower']['credit_score'] = 0
    end

    response['co_borrower'] = {}
    if (loan['CoFirstName'].present? && !loan['CoFirstName'].strip.blank?) || (loan['CoLastName'].present? && !loan['CoLastName'].strip.blank?)
      response['co_borrower']['first_name'] = loan['CoFirstName'].strip if loan['CoFirstName'].present?
      response['co_borrower']['last_name'] = loan['CoLastName'].strip if loan['CoLastName'].present?
      response['co_borrower']['dob'] = EncompassBrokerPuller::get_sftp_time(loan['CoDOB'].strip) if loan['CoDOB'].present?
      response['co_borrower']['email_address'] = loan['CoEmail'].strip if loan['CoEmail'].present?
      response['co_borrower']['phone'] = loan['CoCellPhone'].strip if loan['CoCellPhone'].present?
      response['co_borrower']['cell_phone'] = loan['CoCellPhone'].strip if loan['CoCellPhone'].present?
      response['co_borrower']['work_phone'] = loan['CoCellPhone'].strip if loan['CoCellPhone'].present?
      response['co_borrower']['credit_score'] = 0
    end

    response['property'] = {}
    if loan['PropertyAddress'].present?
      response['property']['name'] = ''
      response['property']['street'] = loan['PropertyAddress'].strip if loan['PropertyAddress'].present?
      response['property']['city'] = loan['PropertyCity'].strip if loan['PropertyCity'].present?
      response['property']['state'] = loan['PropertyState'].strip if loan['PropertyState'].present?
      response['property']['zip'] = loan['PropertyZip'].strip if loan['PropertyZip'].present?
      response['property']['county'] = loan['PropertyCounty'].strip if loan['PropertyCounty'].present?
      response['property']['appraised_value'] = loan['PropertyAppraisedValue'].strip.to_f if loan['PropertyAppraisedValue'].present?
      response['property']['estimated_value'] = loan['PropertyAppraisedValue'].strip.to_f if loan['PropertyAppraisedValue'].present?
      response['property']['purchase_price'] = loan['PropertyAppraisedValue'].strip.to_f if loan['PropertyAppraisedValue'].present?
    end

    response
  end

  def self.locate_app_user(borrower_cell_ph, borrower_email, borrower_home_ph, borrower_work_ph, servicer, company)
    response = []
    app_users = []

    if servicer
      query_app_users = servicer.app_users
                          .includes(:user, :servicer_activation_code, {servicer_profile: {user: :company}})
      query_app_users.each do |au|
        if au.email.present? && au.email == borrower_email
          app_users << au
        elsif au.user&.unformatted_phone.present? && au.user&.unformatted_phone == borrower_home_ph
          app_users << au
        elsif au.user&.unformatted_phone.present? && au.user&.unformatted_phone == borrower_cell_ph
          app_users << au
        elsif au.user&.unformatted_office_phone.present? && au.user&.unformatted_office_phone == borrower_work_ph
          app_users << au
        end
      end
    else
      app_users = AppUser.joins(:user).includes(:servicer_activation_code, {servicer_profile: {user: :company}})
                    .where(users: {email: borrower_email, company_id: company&.id})
      app_users += AppUser.joins(:user).includes(:servicer_activation_code, {servicer_profile: {user: {company: :loan_los}}})
                          .where("users.company_id = ? and users.account_type = 'app_user' and users.unformatted_phone is not null and users.unformatted_phone != '' and users.unformatted_phone in (?, ?, ?)", company&.id, borrower_home_ph, borrower_cell_ph, borrower_work_ph)
    end

    app_users = app_users.uniq
    app_users.each do |app_user|
      Rails.logger.info "found company: #{company.id.to_s}"
      au = app_user
      response << au
      Rails.logger.info "au: #{au.id.to_s}"
    end

    response
  end

  def self.get_date_with_time(unparsed_datetime)
    if unparsed_datetime.present? && unparsed_datetime.to_s.index(":").nil?
      unparsed_datetime = unparsed_datetime.to_s
      unparsed_datetime = "#{unparsed_datetime} #{Time.now.strftime("%H:%M:%S")}"
    elsif unparsed_datetime.present? && unparsed_datetime.to_s.index("00:00:00")
      unparsed_datetime = unparsed_datetime.to_s.gsub(/00\:00\:00/, Time.now.strftime("%H:%M:%S"))
    else
      unparsed_datetime.to_s
    end
  end

  def self.get_time(unparsed_time)
    begin

      if unparsed_time == nil
        nil
      elsif unparsed_time =~ /Date/
        # unusual date format which was being sent f rom Encompass for a while...  Not sure if it's still coming in.
        parsed_time = Time.at(unparsed_time.to_s.gsub('/Date(','').gsub(')/','').to_f/1000) if unparsed_time.present?
        if parsed_time.to_s.starts_with?( '0001-01-01' )
          return nil
        else
          parsed_time
        end
      else
        unparsed_time = unparsed_time.to_s
        # primary date parsing should be handled here.
        valid_formats = ['%a, %d %b %Y %H:%M:%S %Z %z', '%Y-%m-%d %H:%M:%S %z', '%Y-%m-%dT%H:%M:%S%z', '%d-%m-%Y %I:%M:%S %p', '%Y-%m-%d', '%m/%d/%Y', '%m/%d/%Y %I:%M %P']

        valid_formats.each do |format|
          valid = Time.strptime(unparsed_time, format) rescue false

          return valid if valid
        end

        return nil
      end
    rescue
      nil
    end
  end

  def self.get_sftp_time(unparsed_time)
    Date.strptime(unparsed_time, "%m/%d/%Y").to_s rescue Date.strptime(unparsed_time, "%Y-%m-%d").to_s rescue unparsed_time if unparsed_time.present?
    # unparsed_time.gsub!('/','-').to_datetime
  end

  def self.get_date_without_time(unparsed_time)
    Date.strptime(unparsed_time, "%m/%d/%Y").to_s if unparsed_time.present?
    # unparsed_time.gsub!('/','-').to_datetime
  end

  def self.unformat_phone(phone)
    return if phone.blank?
    new_phone = numberize(phone)
    if new_phone.length == 11 && new_phone[0] == '1'
      new_phone = new_phone[1, 10]
    end

    numberize(new_phone)
  end

  def self.numberize(number)
    outstr = ''
    number.each_char { |c|
      isnumber = (c =~ /^[0-9]$/) != nil
      if isnumber
        outstr << c
      end
    }

    outstr
  end

  def self.to_currency(in_value)
    if in_value.present?
      in_value.delete("$").delete(",").to_f
    else
      in_value
    end
  end

  def self.y_n_to_boolean(value)
    return value.present? && value == 'Y'
  end
end
