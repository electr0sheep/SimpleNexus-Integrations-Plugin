class CustomForm < ActiveRecord::Base
  # == Constants ============================================================

  # == Attributes ===========================================================

  # == Extensions ===========================================================

  # == Relationships ========================================================
  belongs_to :owner, polymorphic: true

  # == Validations ==========================================================

  # == Scopes ===============================================================

  # == Callbacks ============================================================
  before_save :prefill_defaults
  before_save :remove_extra_fields
  before_save :remove_redundant_fields
  before_save :reorder_form_def_keys
  before_save :update_number_of_phases_if_needed
  after_save :update_user_forms
  # == Class Methods ========================================================
  def self.get_default_form_def form_type
  	case form_type
		when :prequal, "prequal"
			SystemSetting.prequal_inputs_template
		when :pre_approval, "pre_approval"
			SystemSetting.pre_approval_inputs_template
		when :loan_app, "loan_app"
			SystemSetting.loan_app_template
    when :ob_pricing, "ob_pricing"
      SystemSetting.ob_pricing
    when :ob_pricing_v2, "ob_pricing_v2"
      SystemSetting.ob_pricing_v2
    when :credit_auth_flow, "credit_auth_flow"
      SystemSetting.credit_auth_flow
		end
  end

  def self.allow_state_overrides form_type
  	!form_type.nil? && form_type.to_s != 'loan_app' && form_type.to_s != 'ob_pricing' && form_type.to_s != 'ob_pricing_v2'
  end

  def self.get_default_form_layout form_type
		case form_type.to_s
		when :prequal, "prequal"
			SystemSetting.prequal_layout_template
		when :pre_approval, "pre_approval"
			SystemSetting.pre_approval_layout_template
		end
  end

  def self.get_form_def custom_form
  	JSON.parse( (custom_form.is_a? String) ? custom_form : custom_form.form_def )
  end

  def self.merge *args
  	forms = args.compact
  	# logger.info forms
  	merged_fields = {}

    forms.each do |form|
    	fields = self.get_form_def( form )["fields"]
      next if fields.nil?

      fields.each do |field|
      	next if field.nil? || field["key"].nil?
        if !form.is_a? String
					field["owner"] = { id: form.owner_id, type: form.owner_type }
				end
        merged_fields[field["key"]] = field
      end
    end

		base_form = forms.last
    if base_form
    	merged_def = self.get_form_def( base_form )
	    merged_def["fields"] = merged_fields.sort.to_h.values
	    merged_def.to_json
    end
  end

  def self.populate_from_user form_def_raw, user
    form_def = JSON.parse( form_def_raw )

    if user.servicer_profile.present?
      if form_def["structure"][0].is_a?(Array)
        new_structure = []
        form_def["structure"].each do |phase|
          phase.each do |section|
            new_structure.push( section ) if ( section["roles"].blank? || section["roles"].include?( "servicer" ) )
          end
        end
        form_def["structure"] = new_structure
      else
        form_def["structure"] = form_def["structure"].select{|s| ( s["roles"].blank? || s["roles"].include?( "servicer" ) ) }
      end
    elsif user.app_user.present?
      form_def["structure"] = form_def["structure"].select{|s| ( s["roles"].blank? || s["roles"].include?( "borrower" ) ) }
      if user.app_user
        set_value form_def, 'email', user.app_user.email
        set_value form_def, 'borrower_cell_phone', user.app_user.unformatted_phone
      end
      set_value form_def, 'first_name', user.name
      set_value form_def, 'last_name', user.last_name
      set_value form_def, 'borrower_first_name', user.name
      set_value form_def, 'borrower_last_name', user.last_name
    end

    return form_def
  end

  def self.populate_from_partner form_def, partner = nil

  	if partner
  		set_value form_def, 'partner_name', partner.full_name
  		set_value form_def, 'partner_address', partner.formatted_address
  		set_value form_def, 'partner_street', partner.formatted_street_address
  		set_value form_def, 'partner_city', partner.city
  		set_value form_def, 'partner_state', partner.state
  		set_value form_def, 'partner_zip', partner.zip
  	end

  	form_def
  end

  def self.populate_from_loan form_type, loan
    form_def = JSON.parse( loan.effective_form_def form_type )

  	if loan.is_a? Loan
      borrower_name = ("#{loan.borrower.full_name}".strip if loan.borrower)
      co_borrower_name = ("#{loan.co_borrower.full_name}".strip if loan.co_borrower)
      borrowers_names = borrower_name.blank? ? co_borrower_name : (co_borrower_name.blank? ? borrower_name : "#{borrower_name} & #{co_borrower_name}")

      set_value form_def, 'loan_guid', loan.loan_guid
      set_value form_def, 'all_borrowers_names', borrowers_names
      set_value form_def, 'first_name', loan.borrower&.first_name
      set_value form_def, 'last_name', loan.borrower&.last_name
      set_value form_def, 'borrower_first_name', loan.borrower&.first_name
      set_value form_def, 'borrower_last_name', loan.borrower&.last_name
      set_value form_def, 'borrower_present_address_street', loan.borrower&.street1
      set_value form_def, 'borrower_present_address_city', loan.borrower&.city
      set_value form_def, 'borrower_present_address_state', loan.borrower&.state
      set_value form_def, 'borrower_present_address_zip', loan.borrower&.zip
      set_value form_def, 'coborrower_first_name', (loan.co_borrower.first_name if loan.co_borrower)
      set_value form_def, 'coborrower_last_name', (loan.co_borrower.last_name if loan.co_borrower)
      set_value form_def, 'coborrower_present_address_street', (loan.co_borrower.street1 if loan.co_borrower)
      set_value form_def, 'coborrower_present_address_city', (loan.borrower.city if loan.co_borrower)
      set_value form_def, 'coborrower_present_address_state', (loan.borrower.state if loan.co_borrower)
      set_value form_def, 'coborrower_present_address_zip', (loan.borrower.zip if loan.co_borrower)
      set_value form_def, 'email', loan.borrower&.email
      set_value form_def, 'phone', loan.borrower&.home_phone
      set_value form_def, 'loan_program', loan.loan_program
      set_value form_def, 'loan_amount', loan.loan_amount
      set_value form_def, 'max_loan_amount', loan.max_loan_amount
      set_value form_def, 'loan_term', ("#{loan.loan_term.to_i/12} years" if loan.loan_term)
      set_value form_def, 'loan_type', loan.loan_type
      set_value form_def, 'property_type', loan.property_type
      set_value form_def, 'occupancy_status', loan.occupancy_status
      set_value form_def, 'loan_purpose', loan.loan_purpose
      set_value form_def, 'loan_number', loan.loan_number
      set_value form_def, 'interest_rate', loan.interest_rate
      set_value form_def, 'down_payment_percent', get_percentage(loan.cash_from_borrower,loan.loan_amount).to_s
      set_value form_def, 'down_payment', loan.cash_from_borrower
      set_value form_def, 'property_address', loan.loan_property&.street
      set_value form_def, 'property_city', loan.loan_property&.city
      set_value form_def, 'property_state', loan.loan_property&.state
      set_value form_def, 'property_zip', loan.loan_property&.zip
      set_value form_def, 'appraised_value', loan.loan_property&.appraised_value
      set_value form_def, 'estimated_value', loan.loan_property&.estimated_value
      set_value form_def, 'purchase_price', loan.loan_property&.purchase_price
      set_value form_def, 'monthly_payment', loan.total_monthly_pmt
      set_value form_def, 'apr', loan.apr
      set_value form_def, 'p_and_i_payment', loan.p_and_i_payment
      set_value form_def, 'ltv_percentage', loan.ltv_percentage
      set_value form_def, 'credit_report_expiration_date', loan.credit_report_expiration_date
      set_value form_def, 'cash_to_close', loan.cash_to_close
      set_value form_def, 'relying_on_sale_or_lease_to_qualify', loan.relying_on_sale_or_lease_to_qualify
      set_value form_def, 'relying_on_seller_concessions', loan.relying_on_seller_concessions
      set_value form_def, 'relying_on_down_payment_assistance', loan.relying_on_down_payment_assistance
      set_value form_def, 'lender_has_provided_hud_form_for_fha_loans', loan.lender_has_provided_hud_form_for_fha_loans
      set_value form_def, 'verbal_discussion_of_income_assets_and_debts', loan.verbal_discussion_of_income_assets_and_debts
      set_value form_def, 'lender_has_obtained_tri_merged_residential_credit_report', loan.lender_has_obtained_tri_merged_residential_credit_report
      set_value form_def, 'lender_has_received_paystubs', loan.lender_has_received_paystubs
      set_value form_def, 'lender_has_received_w2s', loan.lender_has_received_w2s
      set_value form_def, 'lender_has_received_personal_tax_returns', loan.lender_has_received_personal_tax_returns
      set_value form_def, 'lender_has_received_corporate_tax_returns', loan.lender_has_received_corporate_tax_returns
      set_value form_def, 'lender_has_received_down_payment_reserves_documentation', loan.lender_has_received_down_payment_reserves_documentation
      set_value form_def, 'lender_has_received_gift_documentation', loan.lender_has_received_gift_documentation
      set_value form_def, 'lender_has_received_credit_liability_documentation', loan.lender_has_received_credit_liability_documentation
      set_value form_def, 'additional_comments', loan.additional_comments
      set_value form_def, 'expiration_date', loan.expiration_date

      form_def = populate_from_partner(form_def, loan&.partner)

    elsif loan.is_a? RemoteLoan
      borrower_name = loan.remote_loan_borrower.full_name.strip if loan.remote_loan_borrower
      co_borrower_name = loan.remote_loan_co_borrower.full_name.strip if loan.remote_loan_co_borrower
      borrowers_names = borrower_name.blank? ? co_borrower_name : (co_borrower_name.blank? ? borrower_name : "#{borrower_name} & #{co_borrower_name}")

      set_value form_def, 'loan_guid', loan.remote_loan_guid
      set_value form_def, 'all_borrowers_names', borrowers_names
      set_value form_def, 'first_name', loan.remote_loan_borrower&.first_name
      set_value form_def, 'last_name', loan.remote_loan_borrower&.last_name
      set_value form_def, 'borrower_first_name', loan.remote_loan_borrower&.first_name
      set_value form_def, 'borrower_last_name', loan.remote_loan_borrower&.last_name
      set_value form_def, 'borrower_present_address_street', loan.remote_loan_borrower&.street1
      set_value form_def, 'borrower_present_address_city', loan.remote_loan_borrower&.city
      set_value form_def, 'borrower_present_address_state', loan.remote_loan_borrower&.state
      set_value form_def, 'borrower_present_address_zip', loan.remote_loan_borrower&.zip
      set_value form_def, 'coborrower_first_name', (loan.remote_loan_co_borrower.first_name if loan.remote_loan_co_borrower)
      set_value form_def, 'coborrower_last_name', (loan.remote_loan_co_borrower.last_name if loan.remote_loan_co_borrower)
      set_value form_def, 'coborrower_present_address_street', (loan.remote_loan_co_borrower.street1 if loan.remote_loan_co_borrower)
      set_value form_def, 'coborrower_present_address_city', (loan.remote_loan_borrower.city if loan.remote_loan_co_borrower)
      set_value form_def, 'coborrower_present_address_state', (loan.remote_loan_borrower.state if loan.remote_loan_co_borrower)
      set_value form_def, 'coborrower_present_address_zip', (loan.remote_loan_borrower.zip if loan.remote_loan_co_borrower)
      set_value form_def, 'email', loan.remote_loan_borrower&.email
      set_value form_def, 'phone', loan.remote_loan_borrower&.home_phone
      set_value form_def, 'loan_program', loan.loan_program
      set_value form_def, 'loan_amount', loan.loan_amount
      set_value form_def, 'loan_term', ("#{loan.loan_term.to_i/12} years" if loan.loan_term)
      set_value form_def, 'loan_type', loan.loan_type
      set_value form_def, 'loan_purpose', loan.loan_purpose
      set_value form_def, 'loan_number', loan.loan_number
      set_value form_def, 'interest_rate', loan.interest_rate
      set_value form_def, 'down_payment_percent', get_percentage(loan.cash_from_borrower,loan.loan_amount).to_s
      set_value form_def, 'down_payment', loan.cash_from_borrower
      set_value form_def, 'property_address', loan.remote_loan_property&.street
      set_value form_def, 'property_city', loan.remote_loan_property&.city
      set_value form_def, 'property_state', loan.remote_loan_property&.state
      set_value form_def, 'property_zip', loan.remote_loan_property&.zip
      set_value form_def, 'appraised_value', loan.remote_loan_property&.appraised_value
      set_value form_def, 'estimated_value', loan.remote_loan_property&.estimated_value
      set_value form_def, 'purchase_price', loan.remote_loan_property&.purchase_price
      set_value form_def, 'monthly_payment', loan.total_monthly_pmt
      set_value form_def, 'apr', loan.apr
      set_value form_def, 'p_and_i_payment', loan.p_and_i_payment
      set_value form_def, 'ltv_percentage', loan.ltv_percentage
      set_value form_def, 'credit_report_expiration_date', loan.credit_report_expiration_date
      set_value form_def, 'cash_to_close', loan.cash_to_close
      set_value form_def, 'relying_on_sale_or_lease_to_qualify', loan.relying_on_sale_or_lease_to_qualify
      set_value form_def, 'relying_on_seller_concessions', loan.relying_on_seller_concessions
      set_value form_def, 'relying_on_down_payment_assistance', loan.relying_on_down_payment_assistance
      set_value form_def, 'lender_has_provided_hud_form_for_fha_loans', loan.lender_has_provided_hud_form_for_fha_loans
      set_value form_def, 'verbal_discussion_of_income_assets_and_debts', loan.verbal_discussion_of_income_assets_and_debts
      set_value form_def, 'lender_has_obtained_tri_merged_residential_credit_report', loan.lender_has_obtained_tri_merged_residential_credit_report
      set_value form_def, 'lender_has_received_paystubs', loan.lender_has_received_paystubs
      set_value form_def, 'lender_has_received_w2s', loan.lender_has_received_w2s
      set_value form_def, 'lender_has_received_personal_tax_returns', loan.lender_has_received_personal_tax_returns
      set_value form_def, 'lender_has_received_corporate_tax_returns', loan.lender_has_received_corporate_tax_returns
      set_value form_def, 'lender_has_received_down_payment_reserves_documentation', loan.lender_has_received_down_payment_reserves_documentation
      set_value form_def, 'lender_has_received_gift_documentation', loan.lender_has_received_gift_documentation
      set_value form_def, 'lender_has_received_credit_liability_documentation', loan.lender_has_received_credit_liability_documentation
      set_value form_def, 'additional_comments', loan.additional_comments
      set_value form_def, 'expiration_date', loan.expiration_date

		end

    return form_def
  end

  def self.get_percentage arg1, arg2
  	arg1 = arg1.to_f
  	arg2 = arg2.to_f
  	if arg2 > 0 && arg1 > 0
  		(arg1/arg2 * 100).round(2)
  	end
  end

  def self.set_value form_def, key, value
  	form_def["values"][key] = value if value
  end

  # == Instance Methods =====================================================
  private

  def prefill_defaults
  	if self.form_def.blank?
  		self.form_def = CustomForm.get_default_form_def self.form_type
  	end

		if self.layout.blank?
			self.layout = CustomForm.get_default_form_layout self.form_type
		end

		if self.state.blank?
			self.state = nil
		end
  end

  def update_number_of_phases_if_needed
    if self.form_type == 'loan_app'
      json = JSON.parse(self.form_def)
      if json["structure"]&.size > 0 && json["structure"][0].is_a?(Hash)
        self.number_of_phases = 1
      elsif json["structure"]&.size > 0 && json["structure"][0].is_a?(Array)
        self.number_of_phases = json["structure"].size
      else
        self.number_of_phases = 0
      end
    end
  end

  def reorder_form_def_keys
  	new_hash = {}
  	form_hash = JSON.parse( self.form_def )
		new_hash["name"] = form_hash["name"] unless form_hash["name"].blank?
		new_hash["structure"] = form_hash["structure"] unless form_hash["structure"].blank?

		form_hash.each do |key, val|
		  next if key == "name" || key == "structure"
		  new_hash[key] = val
		end

		self.form_def = new_hash.to_json
  end

  def remove_extra_fields
    json = JSON.parse(self.form_def)
    fields = json["structure"].flatten.map {|s| s["fields"]}.flatten
    json["fields"].keep_if {|f| fields.include?(f["key"])}
    json["fields"].size.dbg
    self.form_def = json.to_json
  end

  def remove_redundant_fields
  	form_def_json = JSON.parse( self.form_def )
  	default_fields = JSON.parse( CustomForm.get_default_form_def self.form_type )["fields"]
  	form_fields = form_def_json["fields"]
  	custom_fields = []

  	form_fields.each do |f|
  		match = true
  		d = default_fields.find{ |d| d["key"] == f["key"] }

  		if d
				f.each do |k,v|
					if k != "owner" && v != d[k]
						logger.info "found diff at key #{k} when comparing #{v} and #{d[k]}"
						match = false
						break
					end
				end
  		end

  		if !d || !match
				logger.info "adding custom field #{f}"
				custom_fields.push( f )
			end
  	end

  	form_def_json["fields"] = custom_fields
  	self.form_def = form_def_json.to_json
  end

  def update_user_forms
    if owner && (owner.is_a? Company) && form_type == :loan_app
      sp_ids = owner.all_servicer_profiles_chain.map(&:id)
      sac_ids = ServicerActivationCode.where( servicer_profile_id: sp_ids ).pluck( :id )
      user_ids = AppUser.where( activation_code_id: sac_ids ).pluck( :user_id ).compact
      user_loan_apps = UserLoanApp.where( user_id: user_ids, submitted: 0 )

      user_loan_apps.each do |ula|
      	begin
	        values = JSON.parse( ula.loan_app_json )["values"].clone
	        hash = JSON.parse( self.template_json )
	        hash["values"] = values
	        ula.loan_app_json = hash.to_json
	        ula.save
	      rescue JSON::ParserError #loan app may be encrypted if from prod data
	      	unless Rails.env.development?
	      		raise
	      	end
	      end

      end
    end
  end

end
