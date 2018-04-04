# coding: utf-8
class UserLoanApp < ActiveRecord::Base
  include LoanAppCreditAuth
  # == Constants ============================================================

  # == Attributes ===========================================================

  # == Extensions ===========================================================
  attr_encrypted :loan_app_json, key: Rails.application.secrets.attr_encrypted_key, unless: Rails.env.development?

  # == Relationships ========================================================
  belongs_to :app_user, required: false

  # Servicer Submitted Loan App, to be assigned an app user later
  belongs_to :servicer_profile, required: false
  belongs_to :owner_loan, polymorphic: true

  has_many :credit_reports, -> { order 'created_at desc' }, as: :owner, dependent: :destroy
  has_many :loan_docs, as: :owner
  has_many :user_loan_app_logs
  has_many :los_import_credit_reports, -> {where "in_los = 0 AND image IS NOT NULL AND (score_transunion IS NOT NULL OR score_equifax IS NOT NULL or score_experian IS NOT NULL)"}, as: :owner, :class_name => 'CreditReport'

  # == Validations ==========================================================

  # == Scopes ===============================================================

  # == Callbacks ============================================================

  before_save :update_structure
  before_save :create_guid
  before_save :de_obfuscate, if: :loan_app_json_changed?
  before_save :validate_loan_app_json, if: :loan_app_json_changed?
  # after_save  :send_to_los_if_submitted, if: (:submitted_at_changed? && :submitted? && :active?)
  after_save :send_to_los_if_submitted, if: Proc.new { |ula| ula.submitted_at_changed? && ula.submitted? && ula.active?}
  after_create :send_created_event
  after_create :clear_cache
  after_save :clear_cache

  # == Class Methods ========================================================
  def self.obfuscated_fields
  	return ["ssn","coborrower_ssn"]
  end

  def self.obfuscate(string)
	  string.gsub(/\d(?=....)/, 'X')
  end

  def self.get_right_structure json_string, phase=0
    json = JSON.parse(json_string)
    if json["structure"][0].is_a?(Array)
      if phase >= json["structure"].count
        phase = json["structure"].count - 1
      end
      json["structure"] = json["structure"][phase]
      json.to_json
    else
      json_string
    end
  end

  # == Instance Methods =====================================================
  def return_to_user!(ip_address, user_agent, actor=nil)
    self.submitted = false
    # encompass uses submitted_at -- don't set to nil
    # self.submitted_at = nil
    self.rejected = true
    self.phases_complete = 0
    self.save!

    self.delete_consent_documents

    clear_cache

    UserLoanAppLog.new(
      user_loan_app: self,
      phase: self.phases_complete,
      ip_address: ip_address,
      agent: user_agent,
      actor: actor,
      event: 'reject'
    ).save!
  end

  def return_from_los!(ip_address, user_agent, actor=nil)
    self.submitted = false
    self.submitted_at = nil
    self.rejected = true
    self.phases_complete = 0
    self.save!

    self.delete_consent_documents

    clear_cache

    UserLoanAppLog.new(
      user_loan_app: self,
      phase: self.phases_complete,
      ip_address: ip_address,
      agent: user_agent,
      actor: actor,
      event: 'reject'
    ).save!
  end

  def mark_imported!(ip_address, user_agent, actor=nil)
    if self.all_phases_complete?
      self.active = false
    else
      self.active = true
      self.submitted = false
      self.submitted_at = nil
    end
    self.save!
    clear_cache

    UserLoanAppLog.new(
      user_loan_app: self,
      phase: self.phases_complete,
      ip_address: ip_address,
      agent: user_agent,
      actor: actor,
      event: 'imported'
    ).save!
  end

  def archive!(ip_address, user_agent, actor=nil)
    self.active = false
    self.deleted = true
    self.save!
    clear_cache

    UserLoanAppLog.new(
      user_loan_app: self,
      phase: self.phases_complete,
      ip_address: ip_address,
      agent: user_agent,
      actor: actor,
      event: 'archive'
    ).save!
  end

  def activate!(ip_address, user_agent, actor=nil)
    self.active = true
    self.save!
    clear_cache

    UserLoanAppLog.new(
      user_loan_app: self,
      phase: self.phases_complete,
      ip_address: ip_address,
      agent: user_agent,
      actor: actor,
      event: 'activate'
    ).save!
  end

  def servicer_profile
    self.app_user&.servicer_profile || ServicerProfile.find(self.servicer_profile_id)
  end

  def submit(servicer_profile_id, ip_address, user_agent, submitter=nil)
    json = JSON.parse(self.loan_app_json)
    json["currentSection"] = 0
    self.loan_app_json = json.to_json
    self.servicer_profile_id = servicer_profile_id
    self.submitted = true
    self.submitted_at = Time.now
    self.rejected = false
    self.active = true
    self.phases_complete += 1
    self.submission_ip = ip_address
    self.submission_agent = user_agent
    if submitter && submitter.is_a?(AppUser)
      self.app_user = submitter
    end
    self.save!

    self.update_consent_documents(self.phases_complete - 1)

    clear_cache

    UserLoanAppLog.new(
      user_loan_app: self,
      phase: self.phases_complete,
      ip_address: ip_address,
      agent: user_agent,
      actor: submitter,
      event: 'submit'
    ).save!


    if submitter && submitter.is_a?(AppUser)
      job_params = Hash.new
      job_params['sp_id'] = servicer_profile_id
      job_params['app_user_id'] = submitter.id
      job_params['user_loan_app_id'] = self.id

      ::LoanAppSubmittedJob.perform_later(job_params)
    end

    EventProducer::audit_event("user_loan_app", "object" => "UserLoanApp", "id" => self.id, "message" => "Loan App Submitted by #{submitter&.full_name}")

  end

  def obfuscated_loan_app_json
  	if self.loan_app_json.present?
	  	parsed_loan_app = JSON.parse( self.loan_app_json )
	  	if parsed_loan_app["values"].present?
	  		UserLoanApp.obfuscated_fields.each do |field|
	  			if parsed_loan_app["values"][field].present?
	  				parsed_loan_app["values"][field] = UserLoanApp.obfuscate(parsed_loan_app["values"][field])
	  			end
	  		end
	  	end
	  	parsed_loan_app.to_json
    end
  end

  def obfuscated_loan_app_json_for_phase phase=0
    json = obfuscated_loan_app_json
    UserLoanApp.get_right_structure(json, phase)
  end

  def de_obfuscate_loan_app_json json, previous=self.loan_app_json
  	if json.present? && previous.present?
  		new_parsed_loan_app = JSON.parse( json )
	  	current_parsed_loan_app = JSON.parse( previous )

	  	if new_parsed_loan_app["values"].present? && current_parsed_loan_app["values"].present?
	  		UserLoanApp.obfuscated_fields.each do |field|
	  			if new_parsed_loan_app["values"][field].present? &&
	  				current_parsed_loan_app["values"][field].present? &&
	  				(new_parsed_loan_app["values"][field].include? 'X')

	  				new_parsed_loan_app["values"][field] = current_parsed_loan_app["values"][field]
	  			end
	  		end
	  		json = new_parsed_loan_app.to_json
	  	end
  	end

  	json
  end

  def loan_app_fields
    json = JSON.parse(self.loan_app_json)
    json["structure"].flatten.map{|s| s["fields"] if (s["roles"].blank? || s["roles"].include?("borrower"))}.flatten.compact.sort
  end

  def authorization_fields
    possible_auth_keys = [
      'credit_authorization',
      'coborrower_credit_authorization',
      'econsent',
      'econsent_mini',
      'servicer_econsent',
      'servicer_econsent_mini',
      'coborrower_econsent']

    json = JSON.parse(self.loan_app_json)
    if json["fields"]
      reqs = json["fields"].collect{ |f| f if ((f["type"] == "agreement" && loan_app_fields.include?(f["key"])) || possible_auth_keys.include?(f["key"]))
      }.compact
    else
      []
    end
  end

  def borrower_name
    parsed_json = JSON.parse(self.loan_app_json)
    if parsed_json["values"] && parsed_json["values"]["borrower_first_name"].present?
      name = parsed_json["values"]["borrower_first_name"]
      if parsed_json["values"]["borrower_last_name"]
        name << " " << parsed_json["values"]["borrower_last_name"]
      end
      if parsed_json["values"]["borrower_suffix"]
        name << parsed_json["values"]["suffix"]
      end
      return name
    elsif parsed_json["values"] && parsed_json["values"]["first_name"].present?
      name = parsed_json["values"]["first_name"]
      if parsed_json["values"]["last_name"]
        name << " " << parsed_json["values"]["last_name"]
      end
      if parsed_json["values"]["suffix"]
        name << parsed_json["values"]["suffix"]
      end
      return name
    end
    return nil
  end

  def effective_name
  	if self.app_user and self.app_user.user
  		self.app_user.user.full_name
  	elsif self.name
  		self.name
    elsif borrower_name
      self.borrower_name
  	end
  end

  def find_source
    sa = self.submission_agent
    if sa == nil
      ""
    elsif /(android|ios)/i =~ sa
      "SimpleNexus Mobile"
    else
      "SimpleNexus Web"
    end
  end

  def to_fannie_mae_1003
    lo                 = servicer_profile
    # mortgage_types     = { "Conventional" => "01", "CONV" => "01", "VA" => "02", "FarmersHomeAdministration" => "03", "FHA" => "03", "USDA / Rural" => "04", "Other" => "07" }
    # amortization_types = { "AdjustableRate" => "01", "GEM" => "04", "Fixed Rate" => "05", "GPM" => "06", "N/A" => "13" }
    types_of_property = { "Primary Residence" => "1", "Secondary Residence" => "2", "Investment" => "D" }
    loan_purposes = { "Purchase" => "16", "Refinance" => "05", "Construction" => "04", "Other" => "15" }
    marital_statuses = { "Married" => "M", "Unmarried" => "U", "Separated" => "S" }
    other_property_disposition = { "Sold" => "S", "Retained" => "H", "Pending Sale" => "P", "Rental" => "R" }
    other_property_type = {
      "Single Family" => "14",
      "Condominium" => "04",
      "Townhouse" => "16",
      "Co-operative" => "13",
      "Two-to-four unit property" => "15",
      "Multifamily (more than 4 units)" => "18",
      "Manufactured/Mobile Home" => "08",
      "Commercial - Non-Residential" => "02",
      "Mixed Use - Residential" => "F1",
      "Farm" => "05",
      "Home and Business Combined" => "03",
      "Land" => "07" }
    json           = ActiveSupport::JSON.decode( self.loan_app_json )
    values         = json.fetch("values")
    ssn            = ( values["ssn"] || '' ).delete("-")
    coborrower_ssn = ( values["coborrower_ssn"] || '' ).delete("-")
    lines          = []
    has_hmda       = lo&.company&.has_hmda

    # envelope header
    line = [ "EH ", " "*6, " "*25, Time.now.strftime("%Y%m%d") + "   ", ( '%-9.9s' % "SN_#{self.id}" ) ].join('')
    lines << line

    # transaction header
    line = [ "TH ", "T100099-002", ( '%-9.9s' % "SN_#{self.id}" ) ].join('')
    lines << line

    # transaction processing info
    line = [ "TPI", "1.00 ", " "*2, " "*30, "N" ].join('')
    lines << line

    # file identification
    line = [ "000" , "1  ", "3.20 ", "W" ].join('')
    lines << line

    # top of form
    line = [ "00A", "N", "N" ].join('')
    lines << line

    # mortgage type and term
    line = [ "01A", " "*127 ]
    line << ( '%15.2f' % ( fix_num( values[ "loan_amount" ] ).to_f ) )
    line << ( '%7.3f' % "0.000" ) # max lifetime rate increase ###.###
    line << ( '%-3.3s' % ( values["loan_term"] || '' ) )
    line << ( " "*162 )
    lines << line.join('')

    # property information
    line = [ "02A" ]
    # line = [ "02A                                                                                                   F1" ]
    line << ( '%-50.50s' % ( values["property_street"] || '' ) )
    line << ( '%-35.35s' % ( values["property_city"] || '' ) )
    line << ( values["property_state"].present? ? (values["property_state"].split(" - ").last.upcase) : "  " )
    line << ( '%-5.5s' % ( values["property_zip"] || '' ) )
    line << " "*4 # +4
    if values["property_number_of_units"].present?
      line << ( '%03d' % to_int_or_empty(values["property_number_of_units"]) ) # number of units
    else
      line << "001"
    end
    line << "F1"
    line << ( " "*84 )
    lines << line.join('')

    # purpose of loan
    line = [ "02B" ]
    line << " "*2
    line << ( '%-2s' % loan_purposes[ values[ "loan_purpose" ] ])
    line << " "*80  #purpose of loan (other)
    line << ( values["type_of_property"].present? ? types_of_property[ values[ "type_of_property" ] ] : "1" )
    line << " "*60
    line << " "*1
    line << " "*8
    lines << line.join('')

    # title holder name
    line = [ "02C", " "*60 ]
    lines << line.join('')

    # construction or refinance data
    if values['loan_purpose'].present? && values['loan_purpose == "Refinance']
      line = [ "02D" ]
      line << " "*4  # year (lot) acquired
      line << " "*15  # original cost
      line << " "*15  # amount of existing liens
      line << " "*15  # present value of lot
      line << " "*15  # cost of improvements
      line << " "*15  # amount of existing liens
      if values['purpose_of_refinance'].present?
        case values['purpose_of_refinance']
          when 'Cash-out/Consolidation'
            line << "11"
          when 'Cash-Out/Home Improvement'
            line << "04"
          when 'Cash-Out/Other'
            line << "01"
          when 'No Cash-Out Rate/Term'
            line << "F1"
          when 'Limited Cash-Out'
            line << "13"
          else
            line << " "*2
        end
      else
        line << " "*2
      end
      line << " "*80  # describe improvements
      line << " "*1  # improvements: Y = Made, N = To be made, U = Unknown
      line << " "*15  # cost of improvements
      lines << line.join('')
    end

    # down payment
    line = [ "02E" ]
    line << " "*2  # down payment type
    if values['down_payment'].present?
      down_payment = values['down_payment'].to_f
    elsif values["purchase_price"].present?
      if values['down_payment_pct'].present?
        down_payment_pct = fix_num(values['down_payment_pct']).to_f
        down_payment = down_payment_pct * fix_num( values[ "purchase_price" ] ).to_f
      elsif values['loan_amount']
        down_payment = fix_num( values[ "purchase_price" ] ).to_f - fix_num( values['loan_amount'] ).to_f
      else
        down_payment = 0.0
      end
    else
      down_payment = 0.0
    end
    line << ( '%15.2f' % down_payment )
    line << ( '%-80.80s' % ( values["down_payment_explanation"] || '' ) )
    lines << line.join('')

    # applicant data
    line = [ "03A" ]
    line << "BW"
    # line << " "*9 # TODO SSN
    line << ( '%-9.9s' % ssn ) # ssn
    line << ( '%-35.35s' % ( values["first_name"] || '' ) )
    line << ( '%-35.35s' % ( values["middle_name"] || '' ) )
    line << ( '%-35.35s' % ( values["last_name"] || '' ) )
    line << ( '%-4.4s' % ( values["suffix"] || '' ) )
    line << ( '%-10.10s' % ( values["borrower_home_phone"].present? ? values["borrower_home_phone"].gsub(/\D/,"") : " "*10 ) )
    line << " "*3
    if values["school_years"].present?
      line << ( '%02d' % ( to_int_or_empty(values["school_years"])) )
    else
      line << " "*2
    end
    line << ( marital_statuses[ values[ "marital_status" ] ] || " " )
    if values["number_dependents"].present?
      line << ( '%02d' % ( values["number_dependents"] || '' ) )
    else
      line << " "*2
    end
    if values['has_coborrower'].present? && value_is_truthy(values['has_coborrower'])
      line << "Y" # joint application?
    else
      line << "N" # joint application?
    end
    line << ( '%-9.9s' % coborrower_ssn ) # ssn (if joint application)
    if values["dob"].present?
      dob_date = to_date_or_empty(values["dob"],"%Y%m%d")
      line << dob_date
    else
      line << " "*8
    end
    line << ( '%-80.80s' % ( values["email"] || user.email ) )
    lines << line.join('')

    # co-applicant data
    if values["coborrower_first_name"].present?
      line = [ "03A" ]
      line << "QZ"
      # line << " "*9 # TODO SSN
      line << ( '%-9.9s' % coborrower_ssn ) # ssn
      line << ( '%-35.35s' % ( values["coborrower_first_name"] || '' ) )
      line << ( '%-35.35s' % ( values["coborrower_middle_name"] || '' ) )
      line << ( '%-35.35s' % ( values["coborrower_last_name"] || '' ) )
      line << ( '%-4.4s' % ( values["coborrower_suffix"] || '' ) )
      line << ( '%-10.10s' % ( values["coborrower_home_phone"].present? ? values["coborrower_home_phone"].gsub(/\D/,"") : " "*10 ) )
      line << " "*3
      if values["coborrower_school_years"].present?
        line << ( '%02d' % ( to_int_or_empty(values["coborrower_school_years"])) )
      else
        line << " "*2
      end
      line << ( marital_statuses[ values[ "coborrower_marital_status" ] ] || " " )
      if values["coborrower_number_dependents"].present?
        line << ( '%02d' % values["coborrower_number_dependents"] )
      else
        line << " "*2
      end
      line << "Y" # assume a joint application
      line << ( '%-9.9s' % ssn ) # ssn (if joint application)
      if values["coborrower_dob"].present?
        coborrower_dob_date = to_date_or_empty(values["coborrower_dob"],"%Y%m%d")
        line << coborrower_dob_date
      else
        line << " "*8
      end
      line << ( '%-80.80s' % ( values["coborrower_email"] || '' ) )
      lines << line.join('')
    end

    # applicant's address
    if values["address"].present?
      line = [ "03C" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "ZG"  # ZG = Present Address, BH = Mailing Address, F4 = Former Residence
      line << ( '%-50.50s' % ( values["address"] || '' ) )
      line << ( '%-35.35s' % ( values["city"] || '' ) )
      line << ( values["state"].present? ? (values["state"].split(" - ").last.upcase) : "  " )
      line << ( '%-5.5s' % ( values["zip"] || '' ) )
      line << " "*4 # plus 4
      if values['property_own'].present?
        if values['property_own'] == "Own" || value_is_truthy(values['property_own'])
          line << "O"
        elsif values['property_own'] == "Rent"
          line << "R"
        elsif values['property_own'] == "Living Rent Free"
          line << "X"
        else
          line << " "
        end
      else
        line << " "*1 # own/rent/
      end
      if values["property_years"].present?
        line << ( '%02d' % ( to_int_or_empty(values["property_years"])) )
      else
        line << " "*2
      end
      if values["property_months"].present?
        line << ( '%02d' % ( to_int_or_empty(values["property_months"])) )
      else
        line << " "*2
      end
      line << " "*50 # country (not needed)
      lines << line.join('')
    end

    if values["prev_address"].present?
      line = [ "03C" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "F4"  # ZG = Present Address, BH = Mailing Address, F4 = Former Residence
      line << ( '%-50.50s' % ( values["prev_address"] || '' ) )
      line << ( '%-35.35s' % ( values["prev_city"] || '' ) )
      line << ( values["prev_state"].present? ? (values["prev_state"].split(" - ").last.upcase) : "  " )
      line << ( '%-5.5s' % ( values["prev_zip"] || '' ) )
      line << " "*4 # plus 4
      if values['prev_property_own'].present?
        if values['prev_property_own'] == "Own" || value_is_truthy(values['prev_property_own'])
          line << "O"
        elsif values['prev_property_own'] == "Rent"
          line << "R"
        elsif values['prev_property_own'] == "Living Rent Free"
          line << "X"
        else
          line << " "
        end
      else
        line << " "*1 # own/rent/
      end
      if values["prev_property_years"].present?
        line << ( '%02d' % ( to_int_or_empty(values["prev_property_years"])) )
      else
        line << " "*2
      end
      if values["prev_property_months"].present?
        line << ( '%02d' % ( to_int_or_empty(values["prev_property_months"])) )
      else
        line << " "*2
      end
      line << " "*50 # country (not needed)
      lines << line.join('')
    end

    # co-applicant's address
    if values["coborrower_address"].present?
      line = [ "03C" ]
      line << ( '%-9.9s' % coborrower_ssn ) # ssn
      line << "ZG"  # ZG = Present Address, BH = Mailing Address, F4 = Former Residence
      line << ( '%-50.50s' % ( values["coborrower_address"] || '' ) )
      line << ( '%-35.35s' % ( values["coborrower_city"] || '' ) )
      line << ( values["coborrower_state"].present? ? (values["coborrower_state"].split(" - ").last.upcase) : "  " )
      line << ( '%-5.5s' % ( values["coborrower_zip"] || '' ) )
      line << " "*4 # plus 4
      if values['coborrower_property_own'].present?
        if values['coborrower_property_own'] == "Own" || value_is_truthy(values['coborrower_property_own'])
          line << "O"
        elsif values['coborrower_property_own'] == "Rent"
          line << "R"
        elsif values['coborrower_property_own'] == "Living Rent Free"
          line << "X"
        else
          line << " "
        end
      else
        line << " "*1 # own/rent/
      end
      if values["coborrower_property_years"].present?
        line << ( '%02d' % ( to_int_or_empty(values["coborrower_property_years"])) )
      else
        line << " "*2
      end
      if values["coborrower_property_months"].present?
        line << ( '%02d' % ( to_int_or_empty(values["coborrower_property_months"])) )
      else
        line << " "*2
      end
      line << " "*50 # country (not needed)
      lines << line.join('')
    end

    if values["coborrower_prev_address"].present?
      line = [ "03C" ]
      line << ( '%-9.9s' % coborrower_ssn ) # ssn
      line << "F4"  # ZG = Present Address, BH = Mailing Address, F4 = Former Residence
      line << ( '%-50.50s' % ( values["coborrower_prev_address"] || '' ) )
      line << ( '%-35.35s' % ( values["coborrower_prev_city"] || '' ) )
      line << ( values["coborrower_prev_state"].present? ? (values["coborrower_prev_state"].split(" - ").last.upcase) : "  " )
      line << ( '%-5.5s' % ( values["coborrower_prev_zip"] || '' ) )
      line << " "*4 # plus 4
      if values['coborrower_prev_property_own'].present?
        if values['coborrower_prev_property_own'] == "Own" || value_is_truthy(values['coborower_prev_property_own'])
          line << "O"
        elsif values['coborrower_prev_property_own'] == "Rent"
          line << "R"
        elsif values['coborrower_prev_property_own'] == "Living Rent Free"
          line << "X"
        else
          line << " "
        end
      else
        line << " "*1 # own/rent/
      end
      if values["coborrower_prev_property_years"].present?
        line << ( '%02d' % ( to_int_or_empty(values["coborrower_prev_property_years"])) )
      else
        line << " "*2
      end
      if values["coborrower_prev_property_months"].present?
        line << ( '%02d' % ( to_int_or_empty(values["coborrower_prev_property_months"])) )
      else
        line << " "*2
      end
      line << " "*50 # country (not needed)
      lines << line.join('')
    end

    # applicant's current employer
    if values["employer_name"].present?
      line = ["04A"]
      line << ( '%-9.9s' % ssn ) # ssn
      line << ( '%-35.35s' % ( values["employer_name"] || '' ) )
      line << ( '%-35.35s' % ( values["employer_address"] || '' ) )
      line << ( '%-35.35s' % ( values["employer_city"] || '' ) )
      if values["employer_state"].present?
        line << to_state_or_empty(values["employer_state"])
      else
        line << " "*2
      end
      line << ( '%-5.5s' % ( values["employer_zip"] || '' ) )
      line << " "*4 # plus 4
      line << ( boolean_to_y_n(values["is_self_employed"]) ) # self-employed
      if values["employer_years"].present?
        line << ( '%02d' % to_int_or_empty(values["employer_years"]) )
      else
        line << " "*2 # years on job
      end
      if values["employer_months"].present?
        line << ( '%02d' % to_int_or_empty(values["employer_months"]) )
      else
        line << " "*2 # months on job
      end
      if values["line_of_work"].present?
        line << ( '%02d' % to_int_or_empty(values["line_of_work"]) )
      else
        line << " "*2 # years working in this field
      end
      line << ( '%-25.25s' % ( values["job_title"] || '' ) )
      if values["employer_phone"].present?
        line << ( '%-10.10s' % values["employer_phone"] )
      elsif values["work_phone"].present?
        line << ( '%-10.10s' % values["work_phone"] )
      else
        line << " "*10 # business phone
      end
      lines << line.join('')
    end

    # applicant's current employer
    if values["coborrower_employer_name"].present?
      line = ["04A"]
      line << ( '%-9.9s' % coborrower_ssn ) # ssn
      line << ( '%-35.35s' % ( values["coborrower_employer_name"] || '' ) )
      line << ( '%-35.35s' % ( values["coborrower_employer_address"] || '' ) )
      line << ( '%-35.35s' % ( values["coborrower_employer_city"] || '' ) )
      if values["coborrower_employer_state"].present?
        line << to_state_or_empty(values["coborrower_employer_state"])
      else
        line << " "*2
      end
      line << ( '%-5.5s' % ( values["coborrower_employer_zip"] || '' ) )
      line << " "*4 # plus 4
      line << ( boolean_to_y_n(values["coborrower_is_self_employed"]) ) # self-employed
      if values["coborrower_employer_years"].present?
        line << ( '%02d' % to_int_or_empty(values["coborrower_employer_years"]) )
      else
        line << " "*2 # years on job
      end
      if values["coborrower_employer_months"].present?
        line << ( '%02d' % to_int_or_empty(values["coborrower_employer_months"]) )
      else
        line << " "*2 # months on job
      end
      if values["coborrower_line_of_work"].present?
        line << ( '%02d' % to_int_or_empty(values["coborrower_line_of_work"]) )
      else
        line << " "*2 # years working in this field
      end
      line << ( '%-25.25s' % ( values["job_title"] || '' ) )
      if values["coborrower_employer_phone"].present?
        line << ( '%-10.10s' % values["coborrower_employer_phone"] )
      elsif values["coborrower_work_phone"].present?
        line << ( '%-10.10s' % values["coborrower_work_phone"] )
      else
        line << " "*10 # business phone
      end
      lines << line.join('')
    end

    # # housing expense
    line = [ "05H" ]
    line << ( '%-9.9s' % ssn ) # ssn
    line << " "*1 # TODO proposed?
    line << " "*2 # TODO housing payment type code
    line << " "*15 # TODO monthly housing expense amount
    lines << line.join('')

    # income - borrower
    if values["monthly_income"].present?
      line = [ "05I" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "20" # income code, "20" => "Base Employment Income"
      line << ( '%15.2f' % fix_num( values[ "monthly_income" ] ).to_f )
      lines << line.join('')
    end

    # income - coborrower
    if values["coborrower_monthly_income"].present?
      line = [ "05I" ]
      line << ( '%-9.9s' % coborrower_ssn ) # ssn
      line << "20" # income code, "20" => "Base Employment Income"
      line << ( '%15.2f' % fix_num( values[ "coborrower_monthly_income" ] ).to_f )
      lines << line.join('')
    end

    # assets
    if values["assets1"].present?
      line = [ "06C" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "03 " # type of asset, "03" => "Checking Account"
      line << " "*35 # depository name
      line << " "*35 # depository address
      line << " "*35 # depository city
      line << " "*2 # depository state
      line << " "*5 # depository zip
      line << " "*4 # depository plus four
      line << " "*30 # account number
      line << ( '%15.2f' % fix_num( values[ "assets1" ] ).to_f )
      line << " "*7 # number of shares
      line << ( '%-80.80s' % "Other asset 1" ) # asset description
      line << " "*1 # unused
      line << " "*2 # unused
      lines << line.join('')
    end
    if values["assets2"].present?
      line = [ "06C" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "OL " # type of asset, "OL" => "Other Liquid Asset"
      line << " "*35 # depository name
      line << " "*35 # depository address
      line << " "*35 # depository city
      line << " "*2 # depository state
      line << " "*5 # depository zip
      line << " "*4 # depository plus four
      line << " "*30 # account number
      line << ( '%15.2f' % fix_num( values[ "assets2" ] ).to_f )
      line << " "*7 # number of shares
      line << ( '%-80.80s' % "Other asset 2" ) # asset description
      line << " "*1 # unused
      line << " "*2 # unused
      lines << line.join('')
    end
    if values["assets_other"].present?
      line = [ "06C" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "OL " # type of asset, "OL" => "Other Liquid Asset"
      line << " "*35 # depository name
      line << " "*35 # depository address
      line << " "*35 # depository city
      line << " "*2 # depository state
      line << " "*5 # depository zip
      line << " "*4 # depository plus four
      line << " "*30 # account number
      line << ( '%15.2f' % fix_num( values[ "assets_other" ] ).to_f )
      line << " "*7 # number of shares
      line << ( '%-80.80s' % "Other Liquid Assets" ) # asset description
      line << " "*1 # unused
      line << " "*2 # unused
      lines << line.join('')
    end
    if values["savings_account"].present?
      line = [ "06C" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "SG " # type of asset, "SG" => "Savings Account"
      line << ( '%-35.35s' % ( values["bank_name"] || '' ) )
      line << " "*35 # depository address
      line << " "*35 # depository city
      line << " "*2 # depository state
      line << " "*5 # depository zip
      line << " "*4 # depository plus four
      line << " "*30 # account number
      line << ( '%15.2f' % fix_num( values[ "savings_account" ] ).to_f )
      line << " "*7 # number of shares
      line << ( '%-80.80s' % "Savings Account" ) # asset description
      line << " "*1 # unused
      line << " "*2 # unused
      lines << line.join('')
    end
    if values["checking_account"].present?
      line = [ "06C" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "03 " # type of asset, "03" => "Checking Account"
      line << ( '%-35.35s' % ( values["bank_name"] || '' ) )
      line << " "*35 # depository address
      line << " "*35 # depository city
      line << " "*2 # depository state
      line << " "*5 # depository zip
      line << " "*4 # depository plus four
      line << " "*30 # account number
      line << ( '%15.2f' % fix_num( values[ "checking_account" ] ).to_f )
      line << " "*7 # number of shares
      line << ( '%-80.80s' % "Checking Account" ) # asset description
      line << " "*1 # unused
      line << " "*2 # unused
      lines << line.join('')
    end
    if values["assets_retirement"].present?
      line = [ "06C" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "08 " # type of asset, "08" => "Retirement Funds"
      line << " "*35 # depository name
      line << " "*35 # depository address
      line << " "*35 # depository city
      line << " "*2 # depository state
      line << " "*5 # depository zip
      line << " "*4 # depository plus four
      line << " "*30 # account number
      line << ( '%15.2f' % fix_num( values[ "assets_retirement" ] ).to_f )
      line << " "*7 # number of shares
      line << ( '%-80.80s' % "Retirement assets" ) # asset description
      line << " "*1 # unused
      line << " "*2 # unused
      lines << line.join('')
    end

    if values['alimony_amount'].present?
      line = [ "06F" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << "   " # expense type code
      line << ( '%-15.15s' % values['alimony_amount']) # monthly amount
      line << " "*63 # number of months, to whom it is paid
    end

    if values["owns_other_property"].present?
      line = [ "06G" ]
      line << ( '%-9.9s' % ssn ) # ssn
      line << ( '%-35.35s' % ( values["other_property_address"] || " "*35 ) ) # address
      line << ( '%-35.35s' % ( values["other_property_city"] || " "*35 ) ) # city
      if values["other_property_state"].present?
        line << ( '%-2.2s' % to_state_or_empty(values["other_property_state"]) ) # state
      else
        line << ( '%-2.2s' % " "*2 ) # state
      end
      line << ( '%-5.5s' % ( values["other_property_zip"] || " "*5 ) ) # zip
      line << ( '%-4.4s' % ( values["other_property_zip_plus_four"] || " "*4 ) ) # zip plus four
      line << ( values["other_property_disposition"].present? ? other_property_disposition[ values[ "other_property_disposition" ] ] : " " ) # disposition
      line << ( values["other_property_type"].present? ? other_property_type[ values[ "other_property_type" ] ] : "  " ) # type
      line << ( values["other_property_market_value"].present? ? ( '%15.2f' % fix_num( values[ "other_property_market_value" ] ).to_f ) : " "*15 ) # market value
      line << ( values["other_property_mortgage_balance"].present? ? ( '%15.2f' % fix_num( values[ "other_property_mortgage_balance" ] ).to_f ) : " "*15 ) # mortgage balance
      line << ( values["other_property_gross_monthly_rental_income"].present? ? ( '%15.2f' % fix_num( values[ "other_property_gross_monthly_rental_income" ] ).to_f ) : " "*15 ) # gross monthly rental income
      line << ( values["other_property_monthly_mortgage_payment"].present? ? ( '%15.2f' % fix_num( values[ "other_property_monthly_mortgage_payment" ] ).to_f ) : " "*15 ) # monthly mortgage payment
      line << ( values["other_property_monthly_expenses"].present? ? ( '%15.2f' % fix_num( values[ "other_property_monthly_expenses" ] ).to_f ) : " "*15 ) # monthly expenses (maintenance, taxes, etc)
      line << ( values["other_property_net_monthly_rental_income"].present? ? ( '%15.2f' % fix_num( values[ "other_property_net_monthly_rental_income" ] ).to_f ) : " "*15 ) # net monthly rental income
      line << ( values["other_property_is_current_residence"].present? ? ( boolean_to_y_n(values["other_property_is_current_residence"]) ) : " " ) # current_residence
      line << ( values["other_property_is_loan_for_this"].present? ? ( boolean_to_y_n(values["other_property_is_loan_for_this"]) ) : " " ) # is loan for this property?
      line << "01" # asset ID (if there are multiples then we need to adjust this)
      lines << line.join('')
    end

    line = [ "07A" ]
    if values["purchase_price"].present?
      purchase_price = fix_num( values["purchase_price"] ).to_f
    elsif values["loan_amount"].present?
      purchase_price = fix_num( values["loan_amount"] ).to_f + down_payment
    else
      purchase_price = "0.00"
    end
    line << ( '%15.2f' % purchase_price ) # purchase price
    line << ( '%15.2f' % "0.00" ) # alterations, repairs
    line << ( '%15.2f' % "0.00" ) # cost of land
    line << ( '%15.2f' % "0.00" ) # cost of refinance
    line << ( '%15.2f' % "0.00" ) # estimate prepaids
    line << ( '%15.2f' % "0.00" ) # estimated closing costs
    line << ( '%15.2f' % "0.00" ) # fee to initiate mortgage insurance
    line << ( '%15.2f' % "0.00" ) # discount
    line << ( '%15.2f' % "0.00" ) # subordinate financing
    line << ( '%15.2f' % "0.00" ) # closing costs paid by seller
    line << ( '%15.2f' % "0.00" ) # funding fees financed
    lines << line.join('')

    # declarations - borrower
    line = [ "08A" ]
    line << ( '%-9.9s' % ssn ) # ssn
    line << ( values["has_outstanding_judgements"].present? ? ( boolean_to_y_n(values["has_outstanding_judgements"]) ) : " " ) # judgements
    line << ( values["has_bankruptcy"].present? ? ( boolean_to_y_n(values["has_bankruptcy"]) ) : " " ) # bankruptcy
    line << ( values["has_foreclosure"].present? ? ( boolean_to_y_n(values["has_foreclosure"]) ) : " " ) # foreclosure
    line << ( values["party_to_lawsuit"].present? ? ( boolean_to_y_n(values["party_to_lawsuit"]) ) : " " ) # party_to_lawsuit
    line << ( values["has_obligations"].present? ? ( boolean_to_y_n(values["has_obligations"]) ) : " " ) # obligations
    line << ( values["has_delinquent_debt"].present? ? ( boolean_to_y_n(values["has_delinquent_debt"]) ) : " " ) # delinquent_debt
    line << ( values["has_alimony"].present? ? ( boolean_to_y_n(values["has_alimony"]) ) : " " ) # alimony
    line << ( values["is_down_payment_borrowed"].present? ? ( boolean_to_y_n(values['is_down_payment_borrowed']) ) : " " ) # down payment borrowed
    line << ( values["is_comaker_or_endorser"].present? ? ( boolean_to_y_n(values['is_comaker_or_endorser']) ) : " " ) # co-maker or endorser
    if values["is_us_citizen"].present? && boolean_to_y_n(values['is_us_citizen']) == "Y" # citizenship 01 - US, 03 - permanent resident alien, 05 - non-permanent resident alien
      line << "01"
    elsif values["is_permanent_resident"].present? && boolean_to_y_n(values['is_permanent_resident']) == "Y"
      line << "03"
    else
      line << "  "
    end
    line << ( values["intend_to_occupy"].present? ? ( boolean_to_y_n(values['intend_to_occupy']) ) : " " ) # do you intend to occupy?
    line << ( values["has_ownership_interest"].present? ? ( boolean_to_y_n(values['has_ownership_interest']) ) : " " ) # own a home already
    if values["previous_property_type_declaration"].present? # what type of property 1 - primary, 2 - secondary, D - investment
      if values["previous_property_type_declaration"] == "Primary Residence"
        line << "1"
      elsif values["previous_property_type_declaration"] == "Second Home"
        line << "2"
      elsif values["previous_property_type_declaration"] == "Investment Property"
        line << "D"
      else
        line << " "
      end
    else
      line << " "
    end
    if values["previous_property_title_declaration"].present? # how did you hold title 01 - sole, 25 - joint with spouse, 26 - joint with other
      if values["previous_property_title_declaration"] == "Sole Ownership"
        line << "01"
      elsif values["previous_property_title_declaration"] == "Joint With Spouse"
        line << "25"
      elsif values["previous_property_title_declaration"] == "Joint With Other Than Spouse"
        line << "26"
      else
        line << "  "
      end
    else
      line << "  "
    end
    lines << line.join('')

    # declarations - coborrower
    line = [ "08A" ]
    line << ( '%-9.9s' % coborrower_ssn ) # ssn
    line << ( values["coborrower_has_outstanding_judgements"].present? ? ( boolean_to_y_n(values["coborrower_has_outstanding_judgements"]) ) : " " ) # judgements
    line << ( values["coborrower_has_bankruptcy"].present? ? ( boolean_to_y_n(values["coborrower_has_bankruptcy"]) ) : " " ) # bankruptcy
    line << ( values["coborrower_has_foreclosure"].present? ? ( boolean_to_y_n(values["coborrower_has_foreclosure"]) ) : " " ) # foreclosure
    line << ( values["coborrower_party_to_lawsuit"].present? ? ( boolean_to_y_n(values["coborrower_party_to_lawsuit"]) ) : " " ) # party_to_lawsuit
    line << ( values["coborrower_has_obligations"].present? ? ( boolean_to_y_n(values["coborrower_has_obligations"]) ) : " " ) # obligations
    line << ( values["coborrower_has_delinquent_debt"].present? ? ( boolean_to_y_n(values["coborrower_has_delinquent_debt"]) ) : " " ) # delinquent_debt
    line << ( values["coborrower_has_alimony"].present? ? ( boolean_to_y_n(values["coborrower_has_alimony"]) ) : " " ) # alimony
    line << ( values["coborrower_down_payment_borrowed"].present? ? ( boolean_to_y_n(values['coborrower_down_payment_borrowed']) ) : " " ) # down payment borrowed?
    line << ( values["coborrower_is_comaker_or_endorser"].present? ? ( boolean_to_y_n(values['coborrower_is_comaker_or_endorser']) ) : " " ) # co-maker or endorser
    if values["coborrower_is_us_citizen"].present? && boolean_to_y_n(values['coborrower_is_us_citizen']) == "Y" # citizenship 01 - US, 03 - permanent resident alien, 05 - non-permanent resident alien
      line << "01"
    elsif values["coborrower_is_permanent_resident"].present? && boolean_to_y_n(values['coborrower_is_permanent_resident']) == "Y"
      line << "03"
    else
      line << "  "
    end
    line << ( values["coborrower_intend_to_occupy"].present? ? ( boolean_to_y_n(values['coborrower_intend_to_occupy']) ) : " " ) # do you intend to occupy?
    line << ( values["coborrower_has_ownership_interest"].present? ? ( boolean_to_y_n(values['coborrower_has_ownership_interest']) ) : " " ) # own a home already
    if values["coborrower_previous_property_type_declaration"].present? # what type of property 1 - primary, 2 - secondary, D - investment
      if values["coborrower_previous_property_type_declaration"] == "Primary Residence"
        line << "1"
      elsif values["coborrower_previous_property_type_declaration"] == "Second Home"
        line << "2"
      elsif values["coborrower_previous_property_type_declaration"] == "Investment Property"
        line << "D"
      else
        line << " "
      end
    else
      line << " "
    end
    if values["coborrower_previous_property_title_declaration"].present? # how did you hold title 01 - sole, 25 - joint with spouse, 26 - joint with other
      if values["coborrower_previous_property_title_declaration"] == "Sole Ownership"
        line << "01"
      elsif values["coborrower_previous_property_title_declaration"] == "Joint With Spouse"
        line << "25"
      elsif values["coborrower_previous_property_title_declaration"] == "Joint With Other Than Spouse"
        line << "26"
      else
        line << "  "
      end
    else
      line << "  "
    end
    lines << line.join('')

    # government monitoring
    line = [ "10A" ]
    line << ( '%-9.9s' % ssn ) # ssn

      if values["ethnicity"].present?
        line << 'Y'
        if values["ethnicity"] == "Hispanic or Latino"
          line << '1'
        elsif values["ethnicity"] == "Not Hispanic or Latino"
          line << '2'
        else
          line << '3'
        end
      else
        line << 'N'
        line << '4'
      end

    line << " "*30
    if values["gender"].present? && ( values["gender"] == "Male" || values["gender"] == "Female" )
      line << ( values["gender"] == "Male" ? "M" : "F" )
    else
      line << "I"
    end
    lines << line.join('')

    # government monitoring
    if coborrower_ssn.present?
      line = [ "10A" ]
      line << ( '%-9.9s' % coborrower_ssn ) # ssn

      if values["coborrower_ethnicity"].present?
        line << 'Y'
        if values["coborrower_ethnicity"] == "Hispanic or Latino"
          line << '1'
        elsif values["coborrower_ethnicity"] == "Not Hispanic or Latino"
          line << '2'
        else
          line << '3'
        end
      else
        line << 'N'
        line << '4'
      end

      line << " "*30
      if values["coborrower_gender"].present? && ( values["coborrower_gender"] == "Male" || values["coborrower_gender"] == "Female" )
        line << ( values["coborrower_gender"] == "Male" ? "M" : "F" )
      else
        line << "I"
      end
      lines << line.join('')
    end

    # loan originator information
    if lo.present?
      line = [ "10B" ]
      line << "I"
      line << ( '%-60.60s' % lo.full_name )
      line << ( self.submitted_at || self.updated_at ).strftime( "%Y%m%d" )
      line << ( '%-10.10s' % lo.unformatted_phone[0..10] )
      line << ( '%-35.35s' % (lo.company ? lo.company.name : lo.full_name ) )
      line << ( '%-35.35s' % lo.street1 )
      line << ( '%-35.35s' % lo.street2 )
      line << ( '%-35.35s' % lo.city )
      line << ( '%-2.2s' % lo.state.upcase )
      line << ( '%-5.5s' % lo.zip )
      line << " "*4
      lines << line.join('')
    end

    # 10R
    # government monitoring
    line = [ "10R" ]
    line << ( '%-9.9s' % ssn ) # ssn
    line << "6 "
    lines << line.join('')

    if coborrower_ssn.present?
      line = [ "10R" ]
      line << ( '%-9.9s' % coborrower_ssn ) # ssn
      line << "6 "
      lines << line.join('')
    end

    # file type 70
    line = [ "000", "70 ", "3.20 " ]
    lines << line.join('')

    # fannie mae transmittal data
    line = [ "99B" ]
    line << " "*1 # below market financing
    line << " "*2 # owner of existing mortgage
    if values['estimated_property_value'].present?
      epv = values['estimated_property_value']
    elsif values['property_est_value'].present?
      epv = values['property_est_value']
    else
      epv = nil
    end
    if epv.present?
      line << ( '%15.2f' % ( fix_num( values[ "estimated_property_value" ] ).to_f ) )
    else
      line << ( '%15.2f' % '0.00' ) # appraised value
    end
    # line << " "*7 # buydown rate ###.###
    if epv.present?
      line << "02"
    else
      line << ( "  " ) # appraised (actual) value would be 01
    end
    # line << " "*3 # appraisal fieldwork ordered
    # line << " "*60 # appraiser name
    # line << " "*35 # appraiser company
    # line << " "*15 # appraiser license #
    # line << " "*2 # appraiser license state code
    line << ( " "*122 )
    lines << line.join('')

    # ADSLoanOriginatorID
    line = [ "ADS" ]
    line << ( '%-35.35s' % "LoanOriginatorID" )
    line << ( " "*50 )
    lines << line.join('')

    # ADSLoanOriginationCompanyID
    line = [ "ADS" ]
    line << ( '%-35.35s' % "LoanOriginationCompanyID" )
    line << ( " "*50 )
    lines << line.join('')

    # ADSAppraisalIdentifier
    line = [ "ADS" ]
    line << ( '%-35.35s' % "AppraisalIdentifier" )
    line << ( " "*50 )
    lines << line.join('')

    if has_hmda
      lines.push(*hmda_fields(values,ssn,''))
      lines.push(*hmda_fields(values,coborrower_ssn,'coborrower_'))
    end

    # file type 11
    line = [ "000", "11 ", "3.20 " ]
    lines << line.join('')

    # loan characteristics for eligibility
    line = [ "LNC" ]
    line << "F" # lien type code 1 - first, 2 - second, F - Other
    line << " "*1 # loan documentation type
    if values['property_type'].present?
      case values['property_type']
        when 'Single Family'
          line << "01"
        when 'Condo'
          line << "03"
        when 'Multi-Unit Property'
          line << "01"
        when 'Detached Condo'
          line << "09"
        when 'Manufactured Home'
          line << "08"
        when 'PUD'
          line << "04"
        else
          line << " "*2
        end
    else
      line << " "*2 # subject property type code
    end
    line << " "*2 # unused
    line << " "*2 # unused
    line << " "*2 # unused
    line << " "*2 # unused
    line << " "*2 # project classification code
    line << " "*7 # negative amortization limit percent
    line << "N" # balloon?
    line << " "*1 # unused
    line << " "*1 # unused
    line << "N"*1 # homebuyer education completed
    line << ( '%7.3f' % "0.000" ) # max lifetime rate increase ###.###
    line << " "*7 # payment adjustment life percent cap ###.###
    line << " "*15 # payment adjustment life amount cap
    line << "N" # escrow waived?
    line << " "*8 # scheduled closing date YYYYMMDD
    line << " "*8 # scheduled first payment date YYYYMMDD
    line << ( '%7.3f' % "0.000" ) # MI coverage percent ###.###
    line << " "*3 # MI insurer code
    line << ( '%5.2f' % "0.00" ) # APR spread
    line << " "*1 # HOEPA
    line << " "*1 # PreApproval
    lines << line.join('')

    # product identification
    line = [ "PID" ]
    line << " "*30 # production description
    line << " "*15 # product code
    line << " "*5 # product plan number
    lines << line.join('')

    # product characteristics
    line = [ "PCH" ]
    line << " "*3 # mortgage term in months
    line << "N" # assumable
    line << "01" # payment frequency 01 - monthly, 02 - bi-weekly
    line << "N" # prepayment penalty
    line << " " # prepayment restricted
    line << " "*2 # repayment type
    lines << line.join('')

    # transaction trailer
    line = [ "TT ", ( '%-9.9s' % "SN_#{self.id}" ) ]
    lines << line.join('')

    # envelope trailer
    line = [ "ET ", ( '%-9.9s' % "SN_#{self.id}" ) ]
    lines << line.join('')

    lines.join("\r\n") + "\r\n"
  end

  def hmda_fields(values,ssn,borrower)
    newlines = []

    #gender type
    if values[borrower+'sex'].present?
      if values[borrower+'sex'] == "I do not wish to provide this information"
        gender = "InformationNotProvidedUnknown"
      elsif values[borrower+'sex'] == "Not Applicable"
        gender = "NotApplicable"
      else
        gender = values[borrower+'sex']
      end
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDAGenderType" )
      line << ( '%-50.50s' % "#{ssn}:#{gender}" )
      newlines << line.join('')
    else
      gender = nil
    end

    #gender refusal
    if gender == "InformationNotProvidedUnknown"
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDAGenderRefusalIndicator" )
      line << ( '%-50.50s' % "#{ssn}:Y" )
      newlines << line.join('')
    end

    #ethnicity type
    if values[borrower+'ethnicity'].present?
      if values[borrower+'ethnicity'] == "Hispanic or Latino"
        ethnicity = "HispanicOrLatino"
      elsif values[borrower+'ethnicity'] == "Not Hispanic or Latino"
        ethnicity = "NotHispanicOrLatino"
      elsif values[borrower+'ethnicity'] == "I do not wish to provide this information"
        ethnicity = "InformationNotProvidedUnknown"
      elsif values[borrower+'ethnicity'] == "Not Applicable"
        ethnicity = "NotApplicable"
      else
        ethnicity = values[borrower+'ethnicity']
      end
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDAEthnicityType" )
      line << ( '%-50.50s' % "#{ssn}:#{ethnicity}" )
      newlines << line.join('')
    else
      ethnicity = nil
    end

    #ethnicity origin type
    if ethnicity == "HispanicOrLatino" && values[borrower+'ethnicity_latino'].present?
      origin = values[borrower+'ethnicity_latino'].gsub(/\s+/, "")
      if origin == "Other Hispanic or Latino"
        origin = "Other"
      end
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDAEthnicityOriginType" )
      line << ( '%-50.50s' % "#{ssn}:#{origin}" )
      newlines << line.join('')
    else
      origin = nil
    end

    #ethnicity origin type other description
    #if they choose hispanic and then "other"
    if origin == "Other"
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDAEthnicityOriginTypeOtherDesc" )
      line << ( '%-50.50s' % "#{values[borrower+'other_hispanic_or_latino_origin']}" )
      newlines << line.join('')
    end

    #ethnicity refusal indicator
    if ethnicity == "InformationNotProvidedUnknown"
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDAEthnicityRefusalIndicator" )
      line << ( '%-50.50s' % "#{ssn}:Y" )
      newlines << line.join('')
    end

    #race type
    #regular race question
    if values[borrower+'race'].present?
      if values[borrower+'race'] == "I do not wish to provide this information"
        race = "InformationNotProvidedUnknown"
      else
        race = values[borrower+'race'].split(' ').map {|w| w.capitalize}.join
      end
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDARaceType" )
      line << ( '%-50.50s' % "#{ssn}:1:#{race}" )
      newlines << line.join('')
    else
      race = nil
    end

    #race refusal indicator
    if race == "InformationNotProvidedUnknown"
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDARaceRefusalIndicator" )
      line << ( '%-50.50s' % "#{ssn}:Y" )
      newlines << line.join('')
    end

    #race designation type
    #if they say asian to regular race question
    #OR if they say pacific islander to regular race question
    if race == "Asian" && values[borrower+'race_asian'].present?
      race_designation = values[borrower+'race_asian'].split(' ').map {|w| w.capitalize}.join
    elsif race == "NativeHawaiianOrOtherPacificIslander"
      race_designation = values[borrower+'pacific_islander'].split(' ').map {|w| w.capitalize}.join
    end
    if race_designation.present?
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDARaceDesignationType" )
      line << ( '%-50.50s' % "#{ssn}:1:#{race_designation}" )
      newlines << line.join('')
    end

    #race designation other asian description
    #if they say "other asian" to designation type
    if values[borrower+'asian_origin_other'].present?
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDARaceDesignationOtherAsnDesc" )
      line << ( '%-50.50s' % "#{ssn}:1:#{values[borrower+'asian_origin_other']}" )
      newlines << line.join('')
    end

    #race designation other pacific islander description
    #if they say "other pacific islander" to designation type
    if values[borrower+'pacific_islander_other'].present?
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDARaceDesignationOtherPIDesc" )
      line << ( '%-50.50s' % "#{ssn}:1:#{values[borrower+'pacific_islander_other']}" )
      newlines << line.join('')
    end

    #race type additional description
    #if something other than asian or pacific islander chosen as regular race
    if values[borrower+'race_american_indian_other'].present?
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDARaceTypeAdditionalDescription" )
      line << ( '%-50.50s' % "#{ssn}:1:#{values[borrower+'race_american_indian_other']}" )
      newlines << line.join('')
    end

    #ethnicity collected based on visual observation or surname indicator
    if values[borrower+'ethnicity_method'].present?  && (values[borrower+'ethnicity_method'] == "Visual Observation" || values[borrower+'ethnicity_method'] == "Surname")
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDAEthnicityCollectedBasedOnVisual" )
      line << ( '%-50.50s' % "#{ssn}:Y" )
      newlines << line.join('')
    end

    #gender collected based on visual observation or name indicator
    if values[borrower+'gender_method'].present?  && (values[borrower+'gender_method'] == "Visual Observation" || values[borrower+'gender_method'] == "Surname")
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDAGenderCollectedBasedOnVisual" )
      line << ( '%-50.50s' % "#{ssn}:Y" )
      newlines << line.join('')
    end

    #race collected based on visual observation or name indicator
    if values[borrower+'race_method'].present?  && (values[borrower+'race_method'] == "Visual Observation" || values[borrower+'race_method'] == "Surname")
      line = [ "ADS" ]
      line << ( '%-35.35s' % "HMDARaceCollectedBasedOnVisual" )
      line << ( '%-50.50s' % "#{ssn}:Y" )
      newlines << line.join('')
    end

    newlines
  end

  def to_import_json field_mappings:nil, company:nil
    @field_mappings = field_mappings

    mortgage_types = { "Conventional" => "01", "CONV" => "01", "VA" => "02", "FarmersHomeAdministration" => "03", "FHA" => "03", "USDA / Rural" => "04", "Other" => "07" }
    lo             = servicer_profile
    json           = ActiveSupport::JSON.decode( self.loan_app_json )
    values         = json.fetch('values')
    field_arr = json.fetch('fields')
    if company.nil?
      company     = lo&.company
    end
    company_id = company&.id
    has_hmda       = company&.has_hmda

    response = {}

    response['guid'] = self.guid
    response['loan_officer_id'] = servicer_profile.los_user_id
    response['loan_officer_email'] = servicer_profile.email
    response['loan_officer_name'] = servicer_profile.full_name
    # borrower main contact info
    response['borrower'] = {}
    response['borrower']['first_name'] = values['first_name'] || ''
    response['borrower']['middle_name'] = values['middle_name'] || ''
    response['borrower']['last_name'] = values['last_name'] || ''
    response['borrower']['suffix'] = values['suffix'] || ''
    response['borrower']['ssn'] = values['ssn'] || ''
    
    response['borrower']['dob'] = to_date_or_empty(values["dob"])
    response['borrower']['work_phone'] = values['borrower_work_phone'].present? ? values['borrower_work_phone'].gsub(/\D/,"") : ''
    response['borrower']['home_phone'] = values['borrower_home_phone'].present? ? values['borrower_home_phone'].gsub(/\D/,"") : ''
    response['borrower']['cell_phone'] = values['borrower_cell_phone'].present? ? values['borrower_cell_phone'].gsub(/\D/,"") : ''
    response['borrower']['marital_status'] = values['marital_status'] || ''
    response['borrower']['home_email'] = values['email'] || ''
    response['borrower']['work_email'] = values['work_email'] || ''
    response['borrower']['comments'] = values['borrower_comments'] || ''

    # borrower eConsent
    if values.key?('econsent')
      response['borrower']['econsent'] = {}
      econsent_accepted = value_is_truthy(values['econsent'])
      response['borrower']['econsent']['accepted'] = econsent_accepted ? 1 : 0
      response['borrower']['econsent']['ip_address'] = self.submission_ip || ""
      response['borrower']['econsent']['user_agent'] = self.submission_agent || ""
      response['borrower']['econsent']['consent_date'] = "#{self.submitted_at}"
      accepted_text = econsent_accepted ? 'Accepted' : 'Rejected'
      response['borrower']['econsent']['comments'] = "#{accepted_text} from #{self.submission_ip} at #{self.submitted_at} using #{self.submission_agent}"
    end

    # borrower employer
    response['borrower']['company_info'] = {}
    response['borrower']['company_info']['name'] = values['employer_name'] || ''
    response['borrower']['company_info']['street'] = values['employer_address'] || ''
    response['borrower']['company_info']['city'] = values['employer_city'] || ''
    response['borrower']['company_info']['state'] = to_state_or_empty(values['employer_state'])
    response['borrower']['company_info']['zip'] = values['employer_zip'] || ''
    response['borrower']['company_info']['years'] = to_int_or_empty(values['employer_years'])
    response['borrower']['company_info']['months'] = to_int_or_empty(values['employer_months'])

    # borrower present address
    response['borrower']['present_address'] = {}
    response['borrower']['present_address']['street'] = values['address'] || ''
    response['borrower']['present_address']['city'] = values['city'] || ''
    response['borrower']['present_address']['state'] = (
    if values["state"].present?
      values["state"].split(' - ').last.upcase
    else
      ' '
    end)
    response['borrower']['present_address']['zip'] = values['zip'] || ''
    response['borrower']['present_address']['years'] = to_int_or_empty(values['property_years'])
    response['borrower']['present_address']['months'] = to_int_or_empty(values['property_months'])
    response['borrower']['present_address']['own_rent'] = values['property_own'] && value_is_truthy(values['property_own']) ? 'Own' : 'Rent'
    # if values['property_own']
    #   values['custom_FR0115'] = values['property_own'] == 1 ? 'Own' : 'Rent'
    # end

    # borrower mailing address
    if value_is_truthy(values['mailing_same_as_current'])
      values['custom_1819'] = 'Y'
      response['borrower']['mailing_address'] = {}
      response['borrower']['mailing_address']['street'] = values['address'] || ''
      response['borrower']['mailing_address']['city'] = values['city'] || ''
      response['borrower']['mailing_address']['state'] = (
      if values["state"].present?
        values["state"].split(' - ').last.upcase
      else
        ' '
      end)
      response['borrower']['mailing_address']['zip'] = values['zip'] || ''
      response['borrower']['mailing_address']['years'] = to_int_or_empty(values['property_years'])

      response['borrower']['mailing_address']['months'] = to_int_or_empty(values['property_months'])
      response['borrower']['mailing_address']['own_rent'] = values['property_own'] && value_is_truthy(values['property_own']) ? 'Own' : 'Rent'
    else
      response['borrower']['mailing_address'] = {}
      response['borrower']['mailing_address']['street'] = values['mailing_address'] || ''
      response['borrower']['mailing_address']['city'] = values['mailing_city'] || ''
      response['borrower']['mailing_address']['state'] = to_state_or_empty(values['mailing_state'])
      response['borrower']['mailing_address']['zip'] = values['mailing_zip'] || ''
      response['borrower']['mailing_address']['years'] = to_int_or_empty(values['property_years'])

      response['borrower']['mailing_address']['months'] = to_int_or_empty(values['property_months'])
      response['borrower']['mailing_address']['own_rent'] = values['property_own'] && value_is_truthy(values['property_own']) ? 'Own' : 'Rent'
    end

    # borrower prev address
    response['borrower']['prev_address'] = {}
    response['borrower']['prev_address']['street'] = values['prev_address'] || ''
    response['borrower']['prev_address']['city'] = values['prev_city'] || ''
    response['borrower']['prev_address']['state'] = to_state_or_empty(values['prev_state'])
    response['borrower']['prev_address']['zip'] = values['prev_zip'] || ''
    response['borrower']['prev_address']['years'] = to_int_or_empty(values['prev_property_years'])
    response['borrower']['prev_address']['months'] = to_int_or_empty(values['prev_property_months'])
    response['borrower']['prev_address']['own_rent'] = values['prev_property_own'] && value_is_truthy(values['prev_property_own']) ? 'Own' : 'Rent'

    # borrower credit
    response['borrower']['credit'] = {}
    response['borrower']['credit']['authorized'] = value_is_truthy(values['credit_authorization']) ? 1 : 0
    response['borrower']['credit']['auth_date'] = to_date_or_empty(self.submitted_at&.to_s)
    response['borrower']['credit']['auth_method'] = value_is_truthy(values['credit_auth_method']) ? values['credit_auth_method'] : 'Internet'
    values['custom_4079'] = values['credit_auth_notes'] ? values['credit_auth_notes'] : ''
    response['borrower']['credit']['transunion'] = values['credit_transunion'] || values['min_req_fico'] || 0
    response['borrower']['credit']['equifax'] = values['credit_equifax'] || values['min_req_fico'] || 0
    response['borrower']['credit']['experian'] = values['credit_experian'] || values['min_req_fico'] || 0
    response['borrower']['credit']['decision_score'] = values['decision_score'] || values['min_req_fico'] || 0

    last_credit_report = credit_reports.last
    if last_credit_report.present?
      if last_credit_report.credit_ref_number.present?
        response['borrower']['credit']['ref_number'] = last_credit_report.credit_ref_number
      end
    end

    if response['borrower']['credit']['ref_number'].blank?
      response['borrower']['credit']['ref_number'] = values['credit_ref_number'] || ''
    end

    if values['job_title']
      values['custom_FE0110'] = values['job_title']
    end

    if values['borrower_previous_employer_name']
      values['custom_BE0202'] = values['borrower_previous_employer_name']
    end
    if values['borrower_previous_employer_address']
      values['custom_BE0204'] = values['borrower_previous_employer_address']
    end
    if values['borrower_previous_employer_city']
      values['custom_BE0205'] = values['borrower_previous_employer_city']
    end
    if values['borrower_previous_employer_state']
      values['custom_BE0206'] = to_state_or_empty(values['borrower_previous_employer_state'])
    end
    if values['borrower_previous_employer_zip']
      values['custom_BE0207'] = values['borrower_previous_employer_zip']
    end
    if values['borrower_previous_employer_phone']
      values['custom_BE0244'] = values['borrower_previous_employer_phone']
    end
    if values['borrower_previous_employer_position']
      values['custom_BE0237'] = values['borrower_previous_employer_position']
    end
    if values['borrower_previous_employer_years']
      values['custom_BE0213'] = values['borrower_previous_employer_years']
    end
    if values['borrower_previous_line_of_work_years']
      values['custom_BE0215'] = to_int_or_empty(values['borrower_previous_line_of_work_years'])
    end
    if values['borrower_previous_self_employed']
      values['custom_BE0216'] = boolean_to_y_n(values['borrower_previous_self_employed'])
    end
    if values['borrower_previous_employer_months']
      values['custom_BE0233'] = values['borrower_previous_employer_months']
    end
    if values['borrower_previous_employer_monthly_income']
      values['custom_BE0219'] = values['borrower_previous_employer_monthly_income']
    end
    if values['borrower_previous_employer_overtime']
      values['custom_BE0220'] = values['borrower_previous_employer_overtime']
    end
    if values['borrower_previous_employer_bonus']
      values['custom_BE0221'] = values['borrower_previous_employer_bonus']
    end
    if values['borrower_previous_employer_commissions']
      values['custom_BE0222'] = values['borrower_previous_employer_commissions']
    end

    if values['coborrower_previous_employer_name']
      values['custom_CE0202'] = values['coborrower_previous_employer_name']
    end
    if values['coborrower_previous_employer_address']
      values['custom_CE0204'] = values['coborrower_previous_employer_address']
    end
    if values['coborrower_previous_employer_city']
      values['custom_CE0205'] = values['coborrower_previous_employer_city']
    end
    if values['coborrower_previous_employer_state']
      values['custom_CE0206'] = to_state_or_empty(values['coborrower_previous_employer_state'])
    end
    if values['coborrower_previous_employer_zip']
      values['custom_CE0207'] = values['coborrower_previous_employer_zip']
    end
    if values['coborrower_previous_employer_phone']
      values['custom_CE0244'] = values['coborrower_previous_employer_phone']
    end
    if values['coborrower_previous_employer_position']
      values['custom_CE0237'] = values['coborrower_previous_employer_position']
    end
    if values['coborrower_previous_employer_years']
      values['custom_CE0213'] = values['coborrower_previous_employer_years']
    end
     if values['coborrower_previous_line_of_work_years']
      values['custom_CE0216'] = to_int_or_empty(values['coborrower_previous_line_of_work_years'])
    end
    if values['coborrower_previous_self_employed']
      values['custom_CE0215'] = boolean_to_y_n(values['coborrower_previous_self_employed'])
    end
    if values['coborrower_previous_employer_months']
      values['custom_CE0233'] = values['coborrower_previous_employer_months']
    end
    if values['coborrower_previous_employer_monthly_income']
      values['custom_CE0219'] = values['coborrower_previous_employer_monthly_income']
    end
    if values['coborrower_previous_employer_overtime']
      values['custom_CE0220'] = values['coborrower_previous_employer_overtime']
    end
    if values['coborrower_previous_employer_bonus']
      values['custom_CE0221'] = values['coborrower_previous_employer_bonus']
    end
    if values['coborrower_previous_employer_commissions']
      values['custom_CE0222'] = values['coborrower_previous_employer_commissions']
    end

    if values['verify_borrower_question']
      values['custom_4079'] = values['verify_borrower_question'] + "\n" + values['verify_borrower_answer']
    end

    if values['down_payment_explanation']
      values['custom_191'] = values['down_payment_explanation']
    end

    # co_borrower contact and identity info

    if value_is_truthy(values["has_coborrower"])
      response['co_borrower'] = {}
      response['co_borrower']['first_name'] = values['coborrower_first_name'] || ''
      response['co_borrower']['middle_name'] = values['coborrower_middle_name'] || ''
      response['co_borrower']['last_name'] = values['coborrower_last_name'] || ''
      response['co_borrower']['suffix'] = values['coborrower_suffix'] || ''
      response['co_borrower']['ssn'] = values['coborrower_ssn'] || ''
      response['co_borrower']['dob'] = to_date_or_empty(values["coborrower_dob"])
      response['co_borrower']['work_phone'] = values['coborrower_work_phone'].present? ? values['coborrower_work_phone'].gsub(/\D/,'') : ''
      response['co_borrower']['home_phone'] = values['coborrower_home_phone'].present? ? values['coborrower_home_phone'].gsub(/\D/,'') : ''
      response['co_borrower']['cell_phone'] = values['coborrower_cell_phone'].present? ? values['coborrower_cell_phone'].gsub(/\D/,'') : ''
      # response['co_borrower']['marital_status'] = values['coborrower_marital_status'] || ''
      if values['coborrower_marital_status']
        values['custom_84'] = values['coborrower_marital_status']
      end
      response['co_borrower']['home_email'] = values['coborrower_email'] || ''
      response['co_borrower']['work_email'] = values['coborrower_work_email'] || ''
      response['co_borrower']['comments'] = values['co_borrower_comments'] || ''

      # co-borrower eConsent
      if values.key?('coborrower_econsent')
        response['co_borrower']['econsent'] = {}
        co_econsent_accepted = value_is_truthy(values['coborrower_econsent'])
        response['co_borrower']['econsent']['accepted'] = co_econsent_accepted ? 1 : 0
        response['co_borrower']['econsent']['ip_address'] = self.submission_ip || ""
        response['co_borrower']['econsent']['user_agent'] = self.submission_agent || ""
        response['co_borrower']['econsent']['consent_date'] = "#{self.submitted_at}"
        accepted_text = co_econsent_accepted ? 'Accepted' : 'Rejected'
        response['co_borrower']['econsent']['comments'] = "#{accepted_text} from #{self.submission_ip} at #{self.submitted_at} using #{self.submission_agent}"
      end

      # co-borrower employer
      response['co_borrower']['company_info'] = {}
      response['co_borrower']['company_info']['name'] = values['coborrower_employer_name'] || ''
      response['co_borrower']['company_info']['street'] = values['coborrower_employer_address'] || ''
      response['co_borrower']['company_info']['city'] = values['coborrower_employer_city'] || ''
      response['co_borrower']['company_info']['state'] = to_state_or_empty(values['coborrower_employer_state'])
      response['co_borrower']['company_info']['zip'] = values['coborrower_employer_zip'] || ''
      response['co_borrower']['company_info']['years'] = to_int_or_empty(values['coborrower_employer_years'])
      response['co_borrower']['company_info']['months'] = to_int_or_empty(values['coborrower_employer_months'])

      # co-borrower present address
      response['co_borrower']['present_address'] = {}
      response['co_borrower']['present_address']['street'] = values['coborrower_address'] || ''
      response['co_borrower']['present_address']['city'] = values['coborrower_city'] || ''
      response['co_borrower']['present_address']['state'] = to_state_or_empty(values['coborrower_state'])
      response['co_borrower']['present_address']['zip'] = values['coborrower_zip'] || ''
      response['co_borrower']['present_address']['years'] = to_int_or_empty(values['coborrower_property_years'])
      response['co_borrower']['present_address']['months'] = to_int_or_empty(values['coborrower_property_months'])
      response['co_borrower']['present_address']['own_rent'] = values['coborrower_property_own'] && value_is_truthy(values['coborrower_property_own']) ? 'Own' : 'Rent'
      # if values['coborrower_property_own']
      #   values['custom_FR0215'] = values['coborrower_property_own'] == 1 ? 'Own' : 'Rent'
      # end

      # co-borrower previous address
      response['co_borrower']['prev_address'] = {}
      response['co_borrower']['prev_address']['street'] = values['coborrower_prev_address'] || ''
      response['co_borrower']['prev_address']['city'] = values['coborrower_prev_city'] || ''
      response['co_borrower']['prev_address']['state'] = to_state_or_empty(values['coborrower_prev_state'])
      response['co_borrower']['prev_address']['zip'] = values['coborrower_prev_zip'] || ''
      response['co_borrower']['prev_address']['years'] = to_int_or_empty(values['coborrower_prev_property_years'])
      response['co_borrower']['prev_address']['months'] = to_int_or_empty(values['coborrower_prev_property_months'])
      response['co_borrower']['prev_address']['own_rent'] = values['coborrower_prev_property_own'] && value_is_truthy(values['coborrower_prev_property_own']) ? 'Own' : 'Rent'

      if value_is_truthy(values['coborrower_mailing_same_as_current'])
        values['custom_1820'] = 'Y'
        values['custom_1519'] = values['coborrower_address'] || ''
        values['custom_1520'] = values['coborrower_city'] || ''
        values['custom_1521']  = (
        if values["state"].present?
          values["state"].split(' - ').last.upcase
        else
          ' '
        end)
        values['custom_1522']  = values['coborrower_zip'] || ''
      else
        values['custom_1519'] = values['coborrower_mailing_address'] || ''
        values['custom_1520'] = values['coborrower_mailing_city'] || ''
        values['custom_1521'] = to_state_or_empty(values["coborrower_mailing_state"])
        values['custom_1522'] = values['coborrower_mailing_zip'] || ''
      end

      # co-borrower credit
      response['co_borrower']['credit'] = {}
      if (value_is_truthy(response['borrower']['credit']['authorized']) && values["has_coborrower"] && value_is_truthy(values["has_coborrower"]) && values['coborrower_credit_authorization'].blank?) || (values['coborrower_credit_authorization'] && value_is_truthy(values['coborrower_credit_authorization']))
        response['co_borrower']['credit']['authorized'] = 1
        response['co_borrower']['credit']['auth_date'] = to_date_or_empty(self.submitted_at&.to_s)
        response['co_borrower']['credit']['auth_method'] = value_is_truthy(values['coborrower_credit_auth_method']) ? values['coborrower_credit_auth_method'] : 'Internet'
        response['co_borrower']['credit']['transunion'] = values['coborrower_credit_transunion'] || values['min_req_fico'] || 0
        response['co_borrower']['credit']['equifax'] = values['coborrower_credit_equifax'] || values['min_req_fico'] || 0
        response['co_borrower']['credit']['experian'] = values['coborrower_credit_experian'] || values['min_req_fico'] || 0
        response['co_borrower']['credit']['decision_score'] = values['coborrower_decision_score'] || values['min_req_fico'] || 0
        response['co_borrower']['credit']['ref_number'] = values['coborrower_credit_ref_number'] || ''
      end

      values['custom_110'] = values['coborrower_monthly_income'] || 0
      values['custom_85'] = values['coborrower_number_dependents'] || 0
      values['custom_86'] = values['coborrower_dependents_age'] || 0
      values['custom_4007'] = values['coborrower_suffix'] || ''
      if values.key?('coborrower_is_self_employed')
        values['custom_FE0215'] = boolean_to_y_n(values['coborrower_is_self_employed'])
      end

      if values.key?('coborrower_has_outstanding_judgements')
        values['custom_175'] = boolean_to_y_n(values['coborrower_has_outstanding_judgements'])
      end
      if values.key?('coborrower_has_bankruptcy')
        values['custom_266'] = boolean_to_y_n(values['coborrower_has_bankruptcy'])
      end
      if values.key?('coborrower_has_foreclosure')
        values['custom_176'] = boolean_to_y_n(values['coborrower_has_foreclosure'])
      end
      if values.key?('coborrower_party_to_lawsuit')
        values['custom_178'] = boolean_to_y_n(values['coborrower_party_to_lawsuit'])
      end
      if values.key?('coborrower_has_obligations')
        values['custom_1197'] = boolean_to_y_n(values['coborrower_has_obligations'])
      end
      if values.key?('coborrower_has_delinquent_debt')
        values['custom_464'] = boolean_to_y_n(values['coborrower_has_delinquent_debt'])
      end
      if values.key?('coborrower_has_alimony')
        values['custom_179'] = boolean_to_y_n(values['coborrower_has_alimony'])
      end
      if values.key?('coborrower_is_comaker_or_endorser')
        values['custom_177'] = boolean_to_y_n(values['coborrower_is_comaker_or_endorser'])
      end
      if values.key?('coborrower_is_primary_residence')
        values['custom_1343'] = boolean_to_yes_no(values['coborrower_is_primary_residence'])
      end
      if values.key?('coborrower_down_payment_borrowed')
        values['custom_180'] = boolean_to_y_n(values['coborrower_down_payment_borrowed'])
      end

      if values.key?('coborrower_is_us_citizen')
        values['custom_985'] = boolean_to_y_n(values['coborrower_is_us_citizen'])

        if boolean_to_y_n(values['coborrower_is_us_citizen']) == 'N'
          if values.key?('coborrower_is_permanent_resident')
            values['custom_467'] = boolean_to_y_n(values['coborrower_is_permanent_resident'])
          end
        end
      end


      if values.key?('coborrower_has_ownership_interest')
        values['custom_1108'] = boolean_to_yes_no(values['coborrower_has_ownership_interest'])
      end

      if value_is_truthy(values['coborrower_has_ownership_interest'])

        values['custom_1015'] = values['coborrower_previous_property_type_declaration'] || ''
        if values['coborrower_previous_property_type_declaration'] == 'Primary Residence'
          values['custom_1015'] = 'PrimaryResidence'
        elsif values['coborrower_previous_property_type_declaration'] == 'Second Home'
          values['custom_1015'] = 'SecondaryResidence'
        elsif values['coborrower_previous_property_type_declaration'] == 'Investment Property'
          values['custom_1015'] = 'Investment'
        end

        if values['coborrower_previous_property_title_declaration'] == 'Sole Ownership'
          values['custom_1070'] = 'Sole'
        elsif values['coborrower_previous_property_title_declaration'] == 'Joint With Spouse'
          values['custom_1070'] = 'JointWithSpouse'
        elsif values['coborrower_previous_property_title_declaration'] == 'Joint With Other Than Spouse'
          values['custom_1070'] = 'JointWithOtherThanSpouse'
        end

      end

      if values['school_years'].present?
         values['custom_39'] = to_int_or_empty(values['school_years'])
      end
      if values['line_of_work'].present?
         values['custom_FE0116'] = to_int_or_empty(values['line_of_work'])
      end
      if values['coborrower_line_of_work'].present?
         values['custom_FE0216'] = to_int_or_empty(values['coborrower_line_of_work'])
      end
      if values['employer_phone'].present?
         values['custom_FE0117'] = values['employer_phone']
      end
      if values['coborrower_employer_phone'].present?
         values['custom_FE0217'] = values['coborrower_employer_phone']
      end

      if values['rent_payment'].present?
         values['custom_119'] = values['rent_payment']
      end

      if values['mortgage_and_liens_1'].present?
         values['custom_FM0117'] = values['mortgage_and_liens_1']
      end
      if values['mortgage_and_liens_2'].present?
         values['custom_FM0217'] = values['mortgage_and_liens_2']
      end
      if values['mortgage_and_liens_3'].present?
         values['custom_FM0317'] = values['mortgage_and_liens_3']
      end
      if values['mortgage_payments_1'].present?
         values['custom_FM0116'] = values['mortgage_payments_1']
      end
      if values['mortgage_payments_2'].present?
         values['custom_FM0216'] = values['mortgage_payments_2']
      end
      if values['mortgage_payments_3'].present?
         values['custom_FM0316'] = values['mortgage_payments_3']
      end
      if values['insurance_maintenance_taxes_1'].present?
         values['custom_FM0121'] = values['insurance_maintenance_taxes_1']
      end
      if values['insurance_maintenance_taxes_2'].present?
         values['custom_FM0221'] = values['insurance_maintenance_taxes_2']
      end
      if values['insurance_maintenance_taxes_3'].present?
         values['custom_FM0321'] = values['insurance_maintenance_taxes_3']
      end
      if values['gross_rental_income_1'].present?
         values['custom_FM0120'] = values['gross_rental_income_1']
      end
      if values['gross_rental_income_2'].present?
         values['custom_FM0220'] = values['gross_rental_income_2']
      end
      if values['gross_rental_income_3'].present?
         values['custom_FM0320'] = values['gross_rental_income_3']
      end
      if values['real_estate_own_1_address'].present?
         values['custom_FM0104'] = values['real_estate_own_1_address']
      end
      if values['real_estate_own_1_city'].present?
         values['custom_FM0106'] = values['real_estate_own_1_city']
      end
      if values['real_estate_own_1_state'].present?
        values['custom_FM0107'] = to_state_or_empty(values['real_estate_own_1_state'])
      end
      if values['real_estate_own_1_zip'].present?
        values['custom_FM0108'] = values['real_estate_own_1_zip']
      end
      if values['real_estate_own_2_address'].present?
        values['custom_FM0204'] = values['real_estate_own_2_address']
      end
      if values['real_estate_own_2_city'].present?
        values['custom_FM0206'] = values['real_estate_own_2_city']
      end
      if values['real_estate_own_2_state'].present?
        values['custom_FM0207'] = to_state_or_empty(values['real_estate_own_2_state'])
      end
      if values['real_estate_own_2_zip'].present?
        values['custom_FM0208'] = values['real_estate_own_2_zip']
      end
      if values['real_estate_own_3_address'].present?
        values['custom_FM0304'] = values['real_estate_own_3_address']
      end
      if values['real_estate_own_3_city'].present?
        values['custom_FM0306'] = values['real_estate_own_3_city']
      end
      if values['real_estate_own_3_state'].present?
        values['custom_FM0307'] = to_state_or_empty(values['real_estate_own_3_state'])
      end
      if values['real_estate_own_3_zip'].present?
        values['custom_FM0308'] = values['real_estate_own_3_zip']
      end
      if values['property_usage_1'].present?
         values['custom_FM0141'] = values['property_usage_1']
      end
      if values['property_usage_2'].present?
         values['custom_FM0241'] = values['property_usage_2']
      end
      if values['property_usage_3'].present?
         values['custom_FM0341'] = values['property_usage_3']
      end
      if values['real_estate_own_type_of_property_1'].present?
         values['custom_FM0118'] = values['real_estate_own_type_of_property_1']
      end
      if values['real_estate_own_type_of_property_2'].present?
         values['custom_FM0218'] = values['real_estate_own_type_of_property_2']
      end
      if values['real_estate_own_type_of_property_3'].present?
         values['custom_FM0318'] = values['real_estate_own_type_of_property_3']
      end
      if values['present_market_value_1'].present?
         values['custom_FM0119'] = values['present_market_value_1']
      end
      if values['present_market_value_2'].present?
         values['custom_FM0219'] = values['present_market_value_2']
      end
      if values['present_market_value_3'].present?
         values['custom_FM0319'] = values['present_market_value_3']
      end
      if values['net_rental_income_1'].present?
         values['custom_FM0132'] = values['net_rental_income_1']
      end
      if values['net_rental_income_2'].present?
         values['custom_FM0232'] = values['net_rental_income_2']
      end
      if values['net_rental_income_3'].present?
        values['custom_FM0332'] = values['net_rental_income_3']
      end

      if values['has_outstanding_judgements_explanation'].present?
        values['custom_CX.1003.BOR.DECL.169'] = values['has_outstanding_judgements_explanation']
      end

      if values['has_bankruptcy_date'].present?
        values['custom_CX.1003.BOR.DECL.265'] = to_date_or_empty(values['has_bankruptcy_date'])
      end

      if values['has_foreclosure_date'].present?
        values['custom_CX.1003.BOR.DECL.170'] = to_date_or_empty(values['has_foreclosure_date'])
      end

      if values['party_to_lawsuit_explanation'].present?
        values['custom_CX.1003.BOR.DECL.172'] = values['party_to_lawsuit_explanation']
      end

      if values['has_obligations_explanation'].present?
        values['custom_CX.1003.BOR.DECL.1057'] = values['has_obligations_explanation']
      end

      if values['has_delinquent_debt_explanation'].present?
        values['custom_CX.1003.BOR.DECL.463'] = values['has_delinquent_debt_explanation']
      end

      if values['is_down_payment_borrowed_explanation'].present?
        values['custom_CX.1003.BOR.DECL.174'] = values['is_down_payment_borrowed_explanation']
      end

      if values['is_comaker_or_endorser_explanation'].present?
        values['custom_CX.1003.BOR.DECL.171'] = values['is_comaker_or_endorser_explanation']
      end

      if value_is_truthy(values['has_coborrower'])
        if values['coborrower_school_years'].present?
           values['custom_71'] = to_int_or_empty(values['coborrower_school_years'])
        end
        if values['coborrower_has_outstanding_judgements_explanation'].present?
          values['custom_CX.1003.COBOR.DECL.175'] = values['coborrower_has_outstanding_judgements_explanation']
        end
        if values['coborrower_has_bankruptcy_date'].present?
          values['custom_CX.1003.COBOR.DECL.266'] = to_date_or_empty(values['coborrower_has_bankruptcy_date'])
        end
        if values['coborrower_has_foreclosure_date'].present?
          values['custom_CX.1003.COBOR.DECL.176'] = to_date_or_empty(values['coborrower_has_foreclosure_date'])
        end
        if values['coborrower_party_to_lawsuit_explanation'].present?
          values['custom_CX.1003.COBOR.DECL.178'] = values['coborrower_party_to_lawsuit_explanation']
        end
        if values['coborrower_has_obligations_explanation'].present?
          values['custom_CX.1003.COBOR.DECL.1197'] = values['coborrower_has_obligations_explanation']
        end
        if values['coborrower_has_delinquent_debt_explanation'].present?
          values['custom_CX.1003.COBOR.DECL.464'] = values['coborrower_has_delinquent_debt_explanation']
        end
        if values['coborrower_down_payment_borrowed_explanation'].present?
          values['custom_CX.1003.COBOR.DECL.180'] = values['coborrower_down_payment_borrowed_explanation']
        end
        if values['coborrower_is_comaker_or_endorser_explanation'].present?
          values['custom_CX.1003.COBOR.DECL.177'] = values['coborrower_is_comaker_or_endorser_explanation']
        end
        if values['coborrower_alimony_amount'].present?
          values['custom_CX.1003.COBOR.DECL.179'] = values['coborrower_alimony_amount']
        end
      end

      #New flow utilizing multichoice
      if has_hmda
        if value_is_truthy(values['coborrower_provide_demographics'])

          if values['coborrower_demographics_method']
            values['custom_4131'] = values['coborrower_demographics_method']

            if values['demographics_method'] == 'Face-to-face'
              values['custom_4132'] = values['coborrower_ethnicity_method']
              values['custom_4133'] = values['coborrower_race_method']
              values['custom_4134'] = values['coborrower_sex_method']
            end
          else
            values['custom_4131'] = 'Internet'
          end

          if has_hmda_multichoice?
            if values['coborrower_ethnicity'].present?
              values['coborrower_ethnicity'].each do |ethnicity|
              ethnicity = ethnicity.lstrip.gsub("-", "")
                if ethnicity == 'Hispanic or Latino'
                  values['custom_4213'] = 'Y'
                elsif ethnicity == 'Mexican'
                  values['custom_4159'] = 'Y'
                elsif ethnicity == 'Puerto Rican'
                  values['custom_4160'] = 'Y'
                elsif ethnicity == 'Cuban'
                  values['custom_4161'] = 'Y'
                elsif ethnicity == 'Other Hispanic or Latino'
                  values['custom_4162'] = 'Y'
                elsif ethnicity == 'Not Hispanic or Latino'
                  values['custom_4214'] = 'Y'
                elsif ethnicity == 'I do not wish to provide this information'
                  values['custom_4206'] = 'Y'
                elsif ethnicity == 'Not Applicable'
                  values['custom_4215'] = 'Y'
                elsif ethnicity == 'Information Not Provided'
                  values['custom_4246'] = 'Y'
                else
                  values['custom_4188'] = 'Y'
                end
              end
            end
          else
            values['custom_1531'] = values['coborrower_ethnicity']
            if values['coborrower_ethnicity'] == 'Hispanic or Latino'
              values['custom_1531'] = 'Hispanic or Latino'
              case values['coborrower_ethnicity_latino']
                when 'Mexican'
                  values['custom_4159'] = 'Y'
                when 'Puerto Rican'
                  values['custom_4160'] = 'Y'
                when 'Cuban'
                  values['custom_4161'] = 'Y'
                when 'Other Hispanic or Latino'
                  values['custom_4162'] = 'Y'
                  values['custom_4136'] = values['coborrower_other_hispanic_or_latino_origin']
                else
                  values['custom_4162'] = 'Y'
                  values['custom_4136'] = values['coborrower_other_hispanic_or_latino_origin']
              end
            elsif values['coborrower_ethnicity'] == 'Not Hispanic or Latino'
              values['custom_1531'] = 'Not Hispanic or Latino'
            elsif values['coborrower_ethnicity'] == 'I do not wish to provide this information'
              values['custom_1531'] = 'Information not provided'
            else values['coborrower_ethnicity'] == 'Not Applicable'
              values['custom_1531'] = 'Not applicable'
            end
          end

          if values['coborrower_other_hispanic_or_latino_origin']
            values['coborrower_other_hispanic_or_latino_origin'] = values['custom_4136']
          end

          if has_hmda_multichoice?
            if values['coborrower_race'].present?
              values['coborrower_race'].each do |race|
                race = race.lstrip.gsub("-", "")
                if race == 'American Indian or Alaska Native'
                  values['custom_1532'] = 'Y'
                elsif race == "Asian"
                  values['custom_1533'] = 'Y'
                elsif race == 'Asian Indian'
                  values['custom_4163'] = 'Y'
                elsif race == 'Chinese'
                  values['custom_4164'] = 'Y'
                elsif race == 'Filipino'
                  values['custom_4165'] = 'Y'
                elsif race == 'Japanese'
                  values['custom_4166'] = 'Y'
                elsif race == 'Korean'
                  values['custom_4167'] = 'Y'
                elsif race == 'Vietnamese'
                  values['custom_4168'] = 'Y'
                elsif race == 'Other Asian'
                  values['custom_4169'] = 'Y'
                elsif race == 'Black or African American'
                  values['custom_1534'] = 'Y'
                elsif race == 'Native Hawaiian or Other Pacific Islander'
                  values['custom_1535'] = 'Y'
                elsif race == 'Native Hawaiian'
                  values['custom_4170'] = 'Y'
                elsif race == 'Guamanian or Chamorro'
                  values['custom_4171'] = 'Y'
                elsif race == 'Samoan'
                  values['custom_4172'] = 'Y'
                elsif race == 'Other Pacific Islander'
                  values['custom_4173'] = 'Y'
                elsif race == "White"
                  values['custom_1536'] = 'Y'
                elsif race == 'I do not wish to provide this information'
                  values['custom_1537'] = 'Y'
                else race == 'Not applicable'
                  values['custom_1538'] = 'Y'
                end
              end
            end
          else
            case values['coborrower_race']
            when 'American Indian or Alaska Native'
              values['custom_1532'] = 'Y'
              values['custom_4137'] = values['coborrower_race_american_indian_other']
            when "Asian"
              values['custom_1533'] = 'Y'
              case values ['coborrower_race_asian']
                when 'Asian Indian'
                  values['custom_4163'] = 'Y'
                when 'Chinese'
                  values['custom_4164'] = 'Y'
                when 'Filipino'
                  values['custom_4165'] = 'Y'
                when 'Japanese'
                  values['custom_4166'] = 'Y'
                when 'Korean'
                  values['custom_4167'] = 'Y'
                when 'Vietnamese'
                  values['custom_4168'] = 'Y'
                when 'Other Asian'
                  values['custom_4169'] = 'Y'
                  values['custom_4139'] = values['coborrower_asian_origin_other']
                else
                  values['custom_4170'] = 'Y'
                  values['custom_4139'] = values['coborrower_asian_origin_other']
              end
            when 'Black or African American'
              values['custom_1534'] = 'Y'
            when 'Native Hawaiian or Other Pacific Islander'
              values['custom_1535'] = 'Y'
              case values ['coborrower_pacific_islander']
                when 'Native Hawaiian'
                  values['custom_4170'] = 'Y'
                when 'Guamanian or Chamorro'
                  values['custom_4171'] = 'Y'
                when 'Samoan'
                  values['custom_4172'] = 'Y'
                when 'Other Pacific Islander'
                  values['custom_4173'] = 'Y'
                  values['custom_4141'] = values['coborrower_pacific_islander_other']
                else
                  values['custom_4173'] = 'Y'
                  values['custom_4141'] = values['coborrower_pacific_islander_other']
              end
            when "White"
              values['custom_1536'] = 'Y'
            when 'I do not wish to provide this information'
              values['custom_1537'] = 'Y'
              values['custom_4253'] = 'Y'
            else
              values['custom_1538'] = 'Y'
            end
          end

          if values['coborrower_race_american_indian_other']
            values['custom_4137'] = values['coborrower_race_american_indian_other']
          end
          if values['coborrower_asian_origin_other']
            values['custom_4139'] = values['coborrower_asian_origin_other']
          end
          if values['coborrower_pacific_islander_other']
            values['custom_4141'] = values['coborrower_pacific_islander_other']
          end

          case values['coborrower_sex']
            when 'Male'
              values['custom_478'] = values['coborrower_sex']
            when 'Female'
              values['custom_478'] = values['coborrower_sex']
            when 'I do not wish to provide this information'
              values['custom_478'] = 'InformationNotProvided'
            when 'Not Applicable'
              values['custom_478'] = 'NotApplicable'
          end
        end
      else
        if value_is_truthy(values['coborrower_provide_demographics'])
          values['custom_189'] = 'N'
          values['custom_1531'] = values['coborrower_ethnicity']

          if values['coborrower_race']
            case values['coborrower_race']
              when "American Indian or Alaska Native"
                values['custom_1532'] = "Y"
              when "Asian"
                values['custom_1533'] = "Y"
              when "Black or African American"
                values['custom_1534'] = "Y"
              when "Native Hawaiian"
                values['custom_1535'] = "Y"
              when "White"
                values['custom_1536'] = "Y"
              when "Information not provided"
                values['custom_1537'] = "Y"
              when "I do not wish to provide this information"
                values['custom_1537'] = "Y"
            end
          end

          values['custom_478'] = values['coborrower_gender']
        end
      end

      values['custom_112'] = values['coborrower_bonuses'] || 0
      values['custom_113'] = values['coborrower_commission'] || 0
      values['custom_116'] = values['coborrower_other_income'] || 0
      if values['coborrower_checking_account']
        values['custom_DD0224'] = 'CoBorrower'
        values['custom_DD0208'] = 'Checking Account'
        values['custom_DD0211'] = values['coborrower_checking_account'] || 0
      end
      if values['coborrower_savings_account']
        values['custom_DD0224'] = 'CoBorrower'
        values['custom_DD0212'] = 'Savings Account'
        values['custom_DD0215'] = values['coborrower_savings_account'] || 0
      end
      if values['coborrower_assets_retirement']
        values['custom_DD0224'] = 'CoBorrower'
        values['custom_DD0216'] = 'Retirement Funds'
        values['custom_DD0219'] = values['coborrower_assets_retirement'] || 0
      end
      if values['coborrower_assets_other']
        values['custom_DD0224'] = 'CoBorrower'
        values['custom_DD0220'] = 'Other Liquid Assets'
        values['custom_DD0223'] = values['coborrower_assets_other'] || 0
      end

      if values['coborrower_job_title']
        values['custom_FE0210'] = values['coborrower_job_title']
      end

    end # ends has_co_borrower check

    # subject property
    response['property'] = {}
    response['property']['street'] = values['property_street'] || ''
    response['property']['city'] = values['property_city'] || ''
    response['property']['state'] = to_state_or_empty(values['property_state'])
    response['property']['zip'] = values['property_zip'] || ''
    response['property']['estimated_value'] = values['property_est_value'] || ''
    response['property']['appraised_value'] = values['property_appraised_value'] || ''
    if values['property_year_built'].present?
      response['custom_18'] = to_int_or_empty(values['property_year_built'])
    end

    if values['property_number_of_units'].present?
      response['custom_16'] = to_int_or_empty(values['property_number_of_units'])
    end

    if values['monthly_house_expense'].present?
      response['custom_737'] = values['monthly_house_expense']
    end

    # main loan info on application
    response['loan'] = {}
    response['loan']['purchase_price'] = values['purchase_price'].present? ? fix_num(values['purchase_price'] ).to_f : 0.0
    response['loan']['down_payment_pct'] = values['down_payment_pct'].present? ? fix_num(values['down_payment_pct']).to_f : 0.0
    response['custom_1335'] = values['down_payment_amount'].present? ? fix_num(values['down_payment_amount']).to_f : 0.0

    if values["loan_amount"].present?
      response['loan']['loan_amt'] = fix_num( values['loan_amount'] ) || 0
    elsif values["purchase_price"].present? && values['down_payment_pct'].present?
      response['loan']['loan_amt'] = fix_num( values['purchase_price'] ).to_i - (fix_num(values['purchase_price'] ).to_i * fix_num(values['down_payment_pct']).to_i/100)  || 0
    end
    response['loan']['loan_type'] = values['loan_type'] || 0
    response['loan']['est_closing_date'] = ''
    response['loan']['term'] = values['loan_term'] || 0
    if values['loan_purpose'].present?
      if values['loan_purpose'] == 'Refinance' || values['loan_purpose'] == 'No Cash-Out Refinance'
        values['loan_purpose'] = 'NoCash-Out Refinance'
      elsif values['loan_purpose'] == 'Cash-Out Refinance'
        values['loan_purpose'] = 'Cash-Out Refinance'
      elsif values['loan_purpose'] == 'Construction'
        values['loan_purpose'] = 'ConstructionToPermanent'
      else
        values['loan_purpose'] = 'Purchase'
      end
    end
    response['loan']['purpose'] = values['loan_purpose'] || 0
    response['loan']['amort_type'] = 'Fixed'
    response['loan']['application_date'] = "#{self.submitted_at}"

    if values['current_lien']
      values['custom_26'] = values['current_lien']
    end

    if values['current_expense_tax']
      values['custom_123'] = values['current_expense_tax']
    end

    if values['current_expense_hazard_ins']
      values['custom_122'] = values['current_expense_hazard_ins']
    end

    # # INITIALLY THESE ARE VERIFIED WITH APM.
    # if false
    #   if company_id == 111192
    #
    #     #ULDD.FNM.LoanProgramIdentifier = LoanFirstTimeHomebuyer
    #     if values["is_firsttimer"] && value_is_truthy(values["is_firsttimer"])
    #       values['custom_ULDD.FNM.LoanProgramIdentifier'] = "LoanFirstTimeHomebuyer"
    #     end
    #
    #
    #     # from Joe V @ APM
    #     # The fields you provided are used for Earnest Money Deposits for a Purchase transaction.
    #     # Is that how they are being used? If so your fields are correct. However, we can’t drop a value in these field without
    #     # putting a value in the Cash Deposit fields 182 and 1715 which are descriptions. Let me know if this is the intended use.
    #     # Obviously you can have assets on a refi but those amounts would be mapped elsewhere.
    #
    #     if values["loan_purpose"] && values["loan_purpose"] == "Purchase"
    #       values['custom_182'] = "Cash"
    #       values['custom_183'] = values['assets1'] || 0
    #
    #       values['custom_1715'] = "Other Assets"
    #       values['custom_1716'] = values['assets2'] || 0
    #     end
    #
    #   end
    # end

    # Monarch special rules
    if company_id == 8 && values['credit_authorization'] && value_is_truthy(values['credit_authorization'])
      values['custom_CX.CREDITAUTH.ONLINE'] = 'X'
    end

    # OnQ source mapping
    if company_id == 111298
      values['custom_CX.SIMPLENEXUS.SOURCE'] = self.find_source
    end

    # Universal source mapping
    if company_id == 111302
      values['custom_CX.SIMPLENEXUS.SOURCE'] = self.find_source
    end

    # Security National source mapping
    if company_id == 111310
      values['custom_CX.LOANSOURCE'] = self.find_source

      values['CX.BORROWER.CERT.AUTH '] = values['borrowers_certification']
      values['CX.VDC'] = values['voluntary_documentation']

      # values[''] = values['coborrower_voluntary_documentation']
      # values[''] = values['coborrower_borrowers_certification']

    end

    # USA Mortgage source mapping
    if company_id == 111282
      values['custom_CX.SIMPLENEXUS'] = self.find_source
    end

    # First Choice source mapping
    if company_id == 111271
      values['custom_CX.VERBAL.CONSENT'] = self.borrower_name + "- Consent logged @" + self.submitted_at&.strftime("%m/%d/%Y %l:%M:%S %p")
    end

    # Obviously you can have assets on a refi but those amounts would be mapped elsewhere.
    if values['assets1']
      values['custom_183'] = values['assets1'] || 0
      values['custom_182'] = get_field_description('assets1', field_arr)
    end
    if values['assets2']
      values['custom_1716'] = values['assets2'] || 0
      values['custom_1715'] = get_field_description('assets2', field_arr)
    end
    values['custom_212'] = values['assets_retirement'] || 0

    if values.key?('is_down_payment_borrowed')
      values['custom_174'] = boolean_to_y_n(values['is_down_payment_borrowed'])
    end

    #New flow utilizing multichoice
    if has_hmda
      if value_is_truthy(values['provide_demographics'])

        if values['demographics_method']

          values['custom_4143'] = values['demographics_method']

          if values['demographics_method'] == 'Face-to-face'
            values['custom_4121'] = values['ethnicity_method']
            values['custom_4122'] = values['race_method']
            values['custom_4123'] = values['sex_method']
          end
        else
          values['custom_4143'] = 'Internet'
        end

        if has_hmda_multichoice?
          if values['ethnicity'].present?
            values['ethnicity'].each do |ethnicity|
            ethnicity = ethnicity.lstrip.gsub("-", "")
              if ethnicity == 'Hispanic or Latino'
                 values['custom_4210'] = 'Y'
              elsif ethnicity == 'Mexican'
                values['custom_4144'] = 'Y'
              elsif ethnicity == 'Puerto Rican'
                values['custom_4145'] = 'Y'
              elsif ethnicity == 'Cuban'
                values['custom_4146'] = 'Y'
              elsif ethnicity == 'Other Hispanic or Latino'
                values['custom_4147'] = 'Y'
               elsif ethnicity == 'Not Hispanic or Latino'
                values['custom_4211'] = 'Y'
              elsif ethnicity == 'I do not wish to provide this information'
                values['custom_4205'] = 'Y'
              elsif ethnicity == 'Not Applicable'
                values['custom_4212'] = 'Y'
              else
                values['custom_4243'] = 'Y'
              end
            end
          end
        else
          values['custom_1523'] = values['ethnicity']
          if values['ethnicity'] == 'Hispanic or Latino'
            values['custom_1523'] = 'Hispanic or Latino'
            case values['ethnicity_latino']
              when "Mexican"
                values['custom_4144'] = "Y"
              when "Puerto Rican"
                values['custom_4145'] = "Y"
              when "Cuban"
                values['custom_4146'] = "Y"
              when "Other Hispanic or Latino"
                values['custom_4147'] = "Y"
                values['custom_4125'] = values['other_hispanic_or_latino_origin']
              else
                values['custom_4147'] = "Y"
                values['custom_4125'] = values['other_hispanic_or_latino_origin']
            end
          elsif values['ethnicity'] == 'Not Hispanic or Latino'
            values['custom_1523'] = 'Not Hispanic or Latino'
          elsif values['ethnicity'] == 'I do not wish to provide this information'
            values['custom_1523'] = 'Information not provided'
          elsif values['ethnicity'] == 'Not Applicable'
            values['custom_1523'] = 'Not applicable'
          end
        end

        if values['other_hispanic_or_latino_origin']
          values['other_hispanic_or_latino_origin'] = values['custom_4125']
        end

        if has_hmda_multichoice?
          if values['race'].present?
            values['race'].each do |race|
              race = race.lstrip.gsub("-", "")
              if race == "American Indian or Alaska Native"
                values['custom_1524'] = "Y"
              elsif race == "Asian"
                values['custom_1525'] = "Y"
              elsif race == "Asian Indian"
                values['custom_4148'] = 'Y'
              elsif race == "Chinese"
                values['custom_4149'] = 'Y'
              elsif race == "Filipino"
                values['custom_4150'] = 'Y'
              elsif race == "Japanese"
                values['custom_4151'] = 'Y'
              elsif race == "Korean"
                values['custom_4152'] = 'Y'
              elsif race == "Vietnamese"
                values['custom_4153'] = 'Y'
              elsif race == "Other Asian"
                values['custom_4154'] = 'Y'
              elsif race == "Black or African American"
                values['custom_1526'] = 'Y'
              elsif race == "Native Hawaiian or Other Pacific Islander"
                values['custom_1527'] = 'Y'
              elsif race == "Native Hawaiian"
                values['custom_4155'] = 'Y'
              elsif race == "Guamanian or Chamorro"
                values['custom_4156'] = 'Y'
              elsif race == "Samoan"
                values['custom_4157'] = 'Y'
              elsif race == "Other Pacific Islander"
                values['custom_4158'] = 'Y'
              elsif race == "White"
                values['custom_1528'] = 'Y'
              elsif race == "I do not wish to provide this information"
                values['custom_1529'] = 'Y'
              else race == "Not applicable"
                values['custom_1530'] = 'Y'
              end
            end
          end
        else
          case values['race']
          when "American Indian or Alaska Native"
            values['custom_1524'] = "Y"
            values['custom_4126'] = values['race_american_indian_other']
          when "Asian"
            values['custom_1525'] = "Y"
            case values ['race_asian']
              when 'Asian Indian'
                values['custom_4148'] = 'Y'
              when 'Chinese'
                values['custom_4149'] = 'Y'
              when 'Filipino'
                values['custom_4150'] = 'Y'
              when 'Japanese'
                values['custom_4151'] = 'Y'
              when 'Korean'
                values['custom_4152'] = 'Y'
              when 'Vietnamese'
                values['custom_4153'] = 'Y'
              when 'Other Asian'
                values['custom_4154'] = 'Y'
                values['custom_4128'] = values['asian_origin_other']
              else
                values['custom_4154'] = 'Y'
                values['custom_4128'] = values['asian_origin_other']
            end
          when "Black or African American"
            values['custom_1526'] = "Y"
          when "Native Hawaiian or Other Pacific Islander"
            values['custom_1527'] = "Y"
            case values ['pacific_islander']
              when 'Native Hawaiian'
                values['custom_4155'] = 'Y'
              when 'Guamanian or Chamorro'
                values['custom_4156'] = 'Y'
              when 'Samoan'
                values['custom_4157'] = 'Y'
              when 'Other Pacific Islander'
                values['custom_4158'] = 'Y'
                values['custom_4130'] = values['pacific_islander_other']
              else
                values['custom_4154'] = 'Y'
                values['custom_4130'] = values['pacific_islander_other']
            end
          when "White"
            values['custom_1528'] = "Y"
          when "I do not wish to provide this information"
            values['custom_1529'] = "Y"
            values['custom_4252'] = 'Y'
          else
            values['custom_1530'] = "Y"
          end
        end


        if values['race_american_indian_other']
          values['custom_4126'] = values['race_american_indian_other']
        end

        if values['asian_origin_other']
          values['custom_4128'] = values['asian_origin_other']
        end

        if values['pacific_islander_other']
          values['custom_4130'] = values['pacific_islander_other']
        end

        case values['sex']
          when 'Male'
            values['custom_471'] = values['sex']
          when 'Female'
            values['custom_471'] = values['sex']
          when 'I do not wish to provide this information'
            values['custom_471'] = 'InformationNotProvided'
          when 'Not Applicable'
            values['custom_471'] = 'NotApplicable'
        end

        #borrower
        if has_hmda_multichoice? && values['gender'].present? && values['gender'].kind_of?(Array) 
          values['gender'].each do |gender|
            case gender
            when 'Male'
              values['custom_4194'] = 'Y'
            when 'Female'
              values['custom_4193'] = 'Y'
            when 'I do not wish to provide this information'
              values['custom_4195'] = 'Y'
            when 'Information Not Provided'
              values['custom_4245'] = 'Y'
            when 'Not Applicable'
              values['custom_4196'] = 'Y'
            end
          end
        elsif values['gender'].present?
          case values['gender']
          when 'Male'
            values['custom_4193'] = 'N'
            values['custom_4194'] = 'Y'
            values['custom_4195'] = 'N'
          when 'Female'
            values['custom_4193'] = 'Y'
            values['custom_4194'] = 'N'
            values['custom_4195'] = 'N'
          when 'Male and Female'
            values['custom_4193'] = 'Y'
            values['custom_4194'] = 'Y'
            values['custom_4195'] = 'N'
          when 'I do not wish to provide this information'
            values['custom_4193'] = 'N'
            values['custom_4194'] = 'N'
            values['custom_4195'] = 'Y'
            values['custom_4245'] = 'Y'
          end
        end


        #coborrower
        if has_hmda_multichoice? && values['coborrower_gender'].present? && values['coborrower_gender'].kind_of?(Array)
          values['coborrower_gender'].each do |gender|
            case gender
            when 'Male'
              values['custom_4198'] = 'Y'
            when 'Female'
              values['custom_4197'] = 'Y'
            when 'I do not wish to provide this information'
              values['custom_4199'] = 'Y'
            when 'Information Not Provided'
              values['custom_4248'] = 'Y'
            when 'Not Applicable'
              values['custom_4200'] = 'Y'
            when 'No Coapplicant'
              values['custom_4189'] = 'Y'
            end
          end
        elsif values['coborrower_gender'].present?
          case values['coborrower_gender']
          when 'Male'
            values['custom_4197'] = 'N'
            values['custom_4198'] = 'Y'
            values['custom_4199'] = 'N'
          when 'Female'
            values['custom_4197'] = 'Y'
            values['custom_4198'] = 'N'
            values['custom_4199'] = 'N'
          when 'Male and Female'
            values['custom_4197'] = 'Y'
            values['custom_4198'] = 'Y'
            values['custom_4199'] = 'N'
          when 'I do not wish to provide this information'
            values['custom_4197'] = 'N'
            values['custom_4198'] = 'N'
            values['custom_4199'] = 'Y'
            values['custom_4248'] = 'Y'
          end
        end
      end

      # FaceToFace, Internet, Mail, Telephone
      # These should be populated by Encompass business rules.
      # values['custom_479'] = 'Internet'
      # values['custom_1612'] = servicer_profile.full_name
      # values['custom_3238'] = servicer_profile.license.gsub(/\D/,'')
      # values['custom_1823'] = servicer_profile.unformatted_phone
      # values['custom_3968'] = servicer_profile.email

    else
      if value_is_truthy(values['provide_demographics'])
        values['custom_188'] = 'N'
        #   ethnicity race gender
        values['custom_1523'] = values['ethnicity'] || ''

        if values['race'] && values['race'].present?
          case values['race']
            when "American Indian or Alaska Native"
              values['custom_1524'] = "Y"
            when "Asian"
              values['custom_1525'] = "Y"
            when "Black or African American"
              values['custom_1526'] = "Y"
            when "Native Hawaiian"
              values['custom_1527'] = "Y"
            when "White"
              values['custom_1528'] = "Y"
            when "Information not provided"
              values['custom_1529'] = "Y"
            when "I do not wish to provide this information"
              values['custom_1529'] = "Y"
          end
        end

        values['custom_471'] = values['gender'] || 'InformationNotProvidedUnknown'

      end
    end

    if values['military_explanation']
      values['custom_955'] = values['military_explanation']
    end

    if values['legal_name_borrower']
      values['custom_31'] = values['legal_name_borrower']
    end
    if values['legal_name_coborrower']
      values['custom_1602'] = values['legal_name_coborrower']
    end

    if values['title_held']
      values['custom_33'] = values['title_held']
    end
    if values['down_payment_source']
      values['custom_34'] = values['down_payment_source']
    end


    if values['property_type']
      if values['property_type'] == 'Single Family'
        values['custom_1041'] = 'Detached'
      elsif values['property_type'] == 'Condo'
        values['custom_1041'] = 'Condominium'
      elsif values['property_type'] == 'Multi-Unit Property'
        values['custom_1041'] = 'Attached'
      elsif values['property_type'] == 'Townhome'
        values['custom_1041'] = 'DetachedCondo'
      elsif values['property_type'] == 'Detached Condo'
        values['custom_1041'] = 'DetachedCondo'
      elsif values['property_type'] == 'PUD'
        values['custom_1041'] = 'PUD'
      elsif values['property_type'] == 'Cooperative'
        values['custom_1041'] = 'Cooperative'
      elsif values['property_type'] == 'Manufactured Home'
        values['custom_1041'] == 'ManufacturedHousing'
      elsif values['property_type'] == 'High Rise Condominium'
        values['custom_1041'] == 'HighRiseCondominium'
      else
        values['custom_1041'] = 'Detached'
      end
    end

    if values['occupancy_type']
      if values['occupancy_type'] == 'Non-Owner Occupied'
        values['custom_3335'] = 'NonOwnerOccupied'
      else
        values['custom_3335'] = 'OwnerOccupied'
      end
    end

    values['custom_101'] = values['monthly_income'] || 0
    values['custom_53'] = values['number_dependents'] || 0
    values['custom_54'] = values['dependents_age'] || 0
    values['custom_103'] = values['bonuses'] || 0
    values['custom_104'] = values['commission'] || 0
    values['custom_107'] = values['other_income'] || 0
    if values['checking_account']
      values['custom_DD0124'] = 'Borrower'
      values['custom_DD0108'] = 'Checking Account'
      values['custom_DD0111'] = values['checking_account'] || 0
    end
    if values['savings_account']
      values['custom_DD0124'] = 'Borrower'
      values['custom_DD0112'] = 'Savings Account'
      values['custom_DD0115'] = values['savings_account'] || 0
    end
    if values['assets_retirement']
      values['custom_DD0124'] = 'Borrower'
      values['custom_DD0116'] = 'Retirement Funds'
      values['custom_DD0119'] = values['assets_retirement'] || 0
    end
    if values['assets_other']
      values['custom_DD0124'] = 'Borrower'
      values['custom_DD0120'] = 'Other Liquid Assets'
      values['custom_DD0123'] = values['assets_other'] || 0
    end
    if values['assets_gift_funds']
      values['custom_DD0124'] = 'Borrower'
      values['custom_DD0120'] = 'Gifts Total'
      values['custom_DD0123'] = values['assets_gift_funds'] || 0
    end

    values['custom_1821'] = values['estimated_property_value'] || 0
    values['custom_1822'] = values['referral_name'] || ''

    if values['is_veteran']
      values['custom_156'] = boolean_to_y_n(values['is_veteran'])
    end

    # these are placeholders and eventually should be worked into the form
    values['custom_4003'] = values['suffix'] || ''


    if values.key?('is_self_employed')
      values['custom_FE0115'] = boolean_to_y_n(values['is_self_employed'])
    end

    # 350 is read-only
    #values['custom_350'] = values['monthly_liabilities'] || 0

    # values['custom_919'] = values['owns_other_property'] || ''  # READONLY

    if values.key?('has_outstanding_judgements')
      values['custom_169'] = boolean_to_y_n(values['has_outstanding_judgements'])
    end
    if values.key?('has_bankruptcy')
      values['custom_265'] = boolean_to_y_n(values['has_bankruptcy'])
    end
    if values.key?('has_foreclosure')
      values['custom_170'] = boolean_to_y_n(values['has_foreclosure'])
    end
    if values.key?('party_to_lawsuit')
      values['custom_172'] = boolean_to_y_n(values['party_to_lawsuit'])
    end
    if values.key?('has_delinquent_debt')
      values['custom_463'] = boolean_to_y_n(values['has_delinquent_debt'])
    end
    if values.key?('has_obligations')
      values['custom_1057'] = boolean_to_y_n(values['has_obligations'])
    end
    if values.key?('is_comaker_or_endorser')
      values['custom_171'] = boolean_to_y_n(values['is_comaker_or_endorser'])
    end

    if values.key?('has_alimony')
      values['custom_173'] = boolean_to_y_n(values['has_alimony'])
      if value_is_truthy(values['has_alimony'])
        values['custom_271'] = "Alimony or Child Support"
        values['custom_272'] = values['alimony_amount'] || 0
      end
    end


    if values.key?('is_us_citizen')
      values['custom_965'] = boolean_to_y_n(values['is_us_citizen'])
      if boolean_to_y_n(values['is_us_citizen']) == 'N'
        if values.key?('is_permanent_resident')
          values['custom_466'] = boolean_to_y_n(values['is_permanent_resident'])
        end
      end
    end

    if values.key?('is_primary_residence')
      values['custom_418'] = boolean_to_yes_no(values['is_primary_residence'])
    end
    if values.key?('has_ownership_interest')
      values['custom_403'] = boolean_to_yes_no(values['has_ownership_interest'])

      if value_is_truthy(values['has_ownership_interest'])
        # PR, SH, IP
        values['custom_981'] = values['previous_property_type_declaration'] || ''
        if values['previous_property_type_declaration'] == 'Primary Residence'
          values['custom_981'] = 'PrimaryResidence'
        elsif values['previous_property_type_declaration'] == 'Second Home'
          values['custom_981'] = 'SecondaryResidence'
        elsif values['previous_property_type_declaration'] == 'Investment Property'
          values['custom_981'] = 'Investment'
        end

        # PrimaryResidence SecondaryResidence Investment
        # S, SP, O
        # TODO: Fix 1811 - 1811 is the subject property type.  981 is other ownership interest property.
        #if values['custom_981'] && values['custom_981'].present?
        #  if values['custom_981'] == 'PrimaryResidence'
        #    values['custom_1811'] = 'PrimaryResidence'
        #  elsif values['custom_981'] == 'SecondaryResidence'
        #    values['custom_1811'] = 'SecondHome'
        #  else
        #    values['custom_1811'] = 'Investor'
        #  end
        #end

        if values['previous_property_title_declaration']
          if values['previous_property_title_declaration'] == 'Sole Ownership'
            values['custom_1069'] = 'Sole'
          elsif values['previous_property_title_declaration'] == 'Joint With Spouse'
            values['custom_1069'] = 'JointWithSpouse'
          elsif values['previous_property_title_declaration'] == 'Joint With Other Than Spouse'
            values['custom_1069'] = 'JointWithOtherThanSpouse'
          end
        end
      end
    end

    if values.key?('is_firsttimer')
      values['custom_934'] = boolean_to_y_n(values['is_firsttimer'])
    end

    #USA Mortgage
    if values['referral_source']
      values['custom_cx.simplenexusref'] = values['referral_source']
    end

    #Eagle Home authorization
    if values.key?('eagle_authorization')
      values['custom_CX.BA.AUTHVERIFY.B1'] = boolean_to_y_n(values['eagle_authorization'])
      if value_is_truthy(values['eagle_authorization'])
        values['custom_CX.BA.AUTHBY.B1'] = servicer_profile.full_name
        values['custom_CX.BA.AUTHDATE.B1'] = self.submitted_at
        values['custom_CX.BA.AUTHMETHOD.B1'] = 'Internet'
      end
    end

    if values.key?('coborrower_eagle_authorization')
      values['custom_CX.BA.AUTHVERIFY.B2'] = boolean_to_y_n(values['coborrower_eagle_authorization'])
      if value_is_truthy('coborrower_eagle_authorization')
        values['custom_CX.BA.AUTHBY.B2'] = servicer_profile.full_name
        values['custom_CX.BA.AUTHDATE.B2'] = self.submitted_at
        values['custom_CX.BA.AUTHMETHOD.B2'] = 'Internet'
      end
    end

    #Townebank mappings
    if company_id == 8
      values['custom_CX.CREDITAUTH.A1'] = values['mothers_maiden_name']
      values['custom_CX.CREDITAUTH.A2'] = values['graduate_from']
      values['custom_CX.CREDITAUTH.A3'] = values['name_of_street']
      values['custom_CX.CREDITAUTH.A4'] = values['favorite_vacation']
      values['custom_CX.CREDITAUTH.BY'] = values['auth_provided_by']
      values['custom_CX.CREDITAUTH.NAME'] = servicer_profile.full_name
    end


    # other contacts section
    if values['contacts_agent_name']
      values['custom_VEND.X139'] = values['contacts_agent_name']
    end
    if values['contacts_agent_company']
      values['custom_VEND.X133'] = values['contacts_agent_company']
    end
    if values['contacts_agent_phone']
      values['custom_VEND.X140'] = values['contacts_agent_phone']
    end
    if values['contacts_agent_email']
      values['custom_VEND.X141'] = values['contacts_agent_email']
    end
    if values['contacts_agent_cell']
      values['custom_VEND.X500'] = values['contacts_agent_cell']
    end

    unless values['custom_1811']
      if values['type_of_property']
        if values['type_of_property'] == 'Primary Residence'
          values['custom_1811'] = 'PrimaryResidence'
        elsif values['type_of_property'] == 'Secondary Residence'
          values['custom_1811'] = 'SecondHome'
        else
          values['custom_1811'] = 'Investor'
        end
      end
    end

    response['additional_fields'] = []
    values.each_with_index do |addl_val,i|
      if addl_val[0].start_with?('custom_')
        addtl_field = {}
        addtl_field['custom_id'] = addl_val[0].gsub(/custom_/,'')
        addtl_field['value'] = addl_val[1]
        addtl_field['description'] = get_field_description(addtl_field['custom_id'], field_arr)
        response['additional_fields'] << addtl_field
      end
    end

    # hack for APM
    if company_id == 111192
      if value_is_truthy(response['borrower']['credit']['authorized'])
        addtl_field1 = {}
        addtl_field1['custom_id'] = 'CX.CSNT.APP1.BORR1.AUTH'
        addtl_field1['value'] = 'Internet'
        addtl_field1['description'] = 'Credit Auth'
        response['additional_fields'] << addtl_field1

        addtl_field2 = {}
        addtl_field2['custom_id'] = 'CX.CSNT.APP1.BORR1.DT'
        addtl_field2['value'] = "#{self.submitted_at}"
        addtl_field2['description'] = 'Credit Auth Date'
        response['additional_fields'] << addtl_field2
      end

      if value_is_truthy(values["has_coborrower"]) && ((value_is_truthy(response['borrower']['credit']['authorized']) && values['coborrower_credit_authorization'].blank?) || (value_is_truthy(values['coborrower_credit_authorization'])))
        response['co_borrower']['credit']['decision_score'] = nil

        addtl_field4 = {}
        addtl_field4['custom_id'] = 'CX.CSNT.APP1.COBORR1.DT'
        addtl_field4['value'] = "#{self.submitted_at}"
        addtl_field4['description'] = 'Credit Auth Date'
        response['additional_fields'] << addtl_field4

        addtl_field5 = {}
        addtl_field5['custom_id'] = 'CX.CSNT.APP1.COBORR1.AUTH'
        addtl_field5['value'] = 'Internet'
        addtl_field5['description'] = 'Credit Auth'
        response['additional_fields'] << addtl_field5
      end

      addtl_field3 = {}
      addtl_field3['custom_id'] = 'CX.MOBILE.APP'
      addtl_field3['value'] = 'Mobile'
      addtl_field3['description'] = 'Mobile'
      response['additional_fields'] << addtl_field3

    elsif company_id == 109
      # fairway
      addtl_field1 = {}
      addtl_field1['custom_id'] = 'CX.IMPORTLOANOFFICERID'
      addtl_field1['value'] = servicer_profile.los_user_id
      addtl_field1['description'] = 'Encompass ID'
      response['additional_fields'] << addtl_field1
      addtl_field2 = {}
      addtl_field2['custom_id'] = 'CX.VENDORNAME.IMPORT'
      addtl_field2['value'] = 'SimpleNexus'
      addtl_field2['description'] = 'SimpleNexus'
      response['additional_fields'] << addtl_field2
    elsif company_id == 111271
      #first choice home  loans
      response['property']['street'] = 'TBD' if response['property']['street'] == ''

      if response['borrower'] && response['borrower']['econsent'] && value_is_truthy(response['borrower']['econsent']['accepted'])
        addtl_field1 = {}
        addtl_field1['custom_id'] = 'CX.SN.ECONSENT'
        addtl_field1['value'] = "#{self.submitted_at}"
        addtl_field1['description'] = 'Mobile eConsent'
        response['additional_fields'] << addtl_field1
      end

      response['borrower']['econsent'] = {}
      response['borrower']['econsent']['accepted'] = 0
      response['borrower']['econsent']['ip_address'] = ''
      response['borrower']['econsent']['user_agent'] = ''
      response['borrower']['econsent']['consent_date'] = ''
      response['borrower']['econsent']['comments'] = ''

    end


    response
  end

  def to_byte_json

    json           = ActiveSupport::JSON.decode( self.loan_app_json )
    values         = json.fetch('values')
    lo             = servicer_profile
    has_hmda       = lo&.company&.has_hmda
    company_id     = lo&.company&.id

    response = {}

    response['guid'] = self.guid
    response['LoanFileName'] = ''
    # get default org code if we have one - if company user, it's "CORP"
    response['OrgCode'] = 'CORP'
    if servicer_profile&.user&.parent_organization
      response['OrgCode'] = servicer_profile&.user&.parent_organization.name
    end

    property_state = response['PropertyState'] = to_state_or_empty(values['property_state'])
    response['PropertyState'] = property_state
    response['TemplateName'] = '' # in case we get to using templates.
    response['LOUserName'] = servicer_profile.los_user_id
    response['lstFields'] = []

    response['lstFields'] << {'FieldID': 'Bor1.FirstName', 'Value': values['first_name'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1.MiddleName', 'Value': values['middle_name'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1.LastName', 'Value': values['last_name'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1.SSN', 'Value': values['ssn'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1.DOB', 'Value': to_date_or_empty(values["dob"])}
    # response['lstFields'] << {'FieldID': 'Bor1.WorkPhoneFormatted', 'Value': values['borrower_work_phone'].present? ? values['borrower_work_phone'].gsub(/\D/, '') : ''}
    response['lstFields'] << {'FieldID': 'Bor1.HomePhone', 'Value': values['borrower_home_phone'].present? ? values['borrower_home_phone'].gsub(/\D/, '') : ''}
    response['lstFields'] << {'FieldID': 'Bor1.MobilePhone', 'Value': values['borrower_cell_phone'].present? ? values['borrower_cell_phone'].gsub(/\D/, '') : ''}
    response['lstFields'] << {'FieldID': 'Bor1.MaritalStatus', 'Value': values['marital_status'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1.Email', 'Value': values['email'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1.MailingCity', 'Value': values['mailing_city'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1.MailingStreet', 'Value': values['mailing_address'] || ''}
    mailing_state = to_state_or_empty(values["mailing_state"])
    response['lstFields'] << {'FieldID': 'Bor1.MailingState', 'Value': mailing_state}
    response['lstFields'] << {'FieldID': 'Bor1.MailingZip', 'Value': values['mailing_zip'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Res.NoYears', 'Value': values['property_years'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Res.NoMonths', 'Value': values['property_months'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Res.LivingStatus', 'Value': values['property_own'] && value_is_truthy(values['property_own']) ? 1 : 2}

    # # borrower eConsent
    # if values['econsent'].present?
    #   response['borrower']['econsent'] = {}
    #   econsent_accepted = value_is_truthy(values['econsent'])
    #   response['borrower']['econsent']['accepted'] = econsent_accepted ? 1 : 0
    #   response['borrower']['econsent']['ip_address'] = self.submission_ip || ""
    #   response['borrower']['econsent']['user_agent'] = self.submission_agent || ""
    #   response['borrower']['econsent']['consent_date'] = "#{self.submitted_at}"
    #   accepted_text = econsent_accepted ? 'Accepted' : 'Rejected'
    #   response['borrower']['econsent']['comments'] = "#{accepted_text} from #{self.submission_ip} at #{self.submitted_at} using #{self.submission_agent}"
    # end
    #

    # # borrower employer
    response['lstFields'] << {'FieldID': 'Bor1Emp.Name', 'Value': values['employer_name'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Emp.Street', 'Value': values['employer_address'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Emp.City', 'Value': values['employer_city'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Emp.State', 'Value': to_state_or_empty(values['employer_state'])}

    response['lstFields'] << {'FieldID': 'Bor1Emp.Zip', 'Value': values['employer_zip'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Emp.YearsOnJob', 'Value': to_int_or_empty(values['employer_years'])}
    # response['borrower']['company_info']['months'] = to_int_or_empty(values['employer_months'])

    # # borrower present address
    response['lstFields'] << {'FieldID': 'Bor1Res.Street', 'Value': values['address'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Res.City', 'Value': values['city'] || ''}
    present_state = to_state_or_empty(values['state'])
    response['lstFields'] << {'FieldID': 'Bor1Res.State', 'Value': present_state}
    response['lstFields'] << {'FieldID': 'Bor1Res.Zip', 'Value': values['zip'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Res.NoYears', 'Value': values['property_years'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Res.NoMonths', 'Value': values['property_months'] || ''}
    response['lstFields'] << {'FieldID': 'Bor1Res.LivingStatus', 'Value': values['property_own'] && value_is_truthy(values['property_own']) ? 1 : 2}

    # # # borrower prev address
    # response['borrower']['prev_address'] = {}
    # response['borrower']['prev_address']['street'] = values['prev_address'] || ''
    # response['borrower']['prev_address']['city'] = values['prev_city'] || ''
    # response['borrower']['prev_address']['state'] = (
    # if values["prev_state"].present?
    #   values['prev_state'].split(' - ').last.upcase
    # else
    #   ''
    # end)
    # response['borrower']['prev_address']['zip'] = values['prev_zip'] || ''
    # response['borrower']['prev_address']['years'] = to_int_or_empty(values['prev_property_years'])
    # response['borrower']['prev_address']['months'] = to_int_or_empty(values['prev_property_months'])
    # response['borrower']['prev_address']['own_rent'] = values['prev_property_own'] && value_is_truthy(values['prev_property_own']) ? 'Own' : 'Rent'
    #
    # # borrower credit
    response['lstFields'] << {'FieldID': 'Bor1.OKToPullCredit', 'Value': value_is_truthy(values['credit_authorization']) ? 'Yes' : 'No'}
    response['lstFields'] << {'FieldID': 'Bor1.TransUnionScore', 'Value': values['credit_transunion'] || values['min_req_fico'] || 0}
    response['lstFields'] << {'FieldID': 'Bor1.EquifaxScore', 'Value': values['credit_equifax'] || values['min_req_fico'] || 0}
    response['lstFields'] << {'FieldID': 'Bor1.ExperianScore', 'Value': values['credit_experian'] || values['min_req_fico'] || 0}
    found_credit_ref = false
    last_credit_report = credit_reports.last
    if last_credit_report.present?
      if last_credit_report.credit_ref_number.present?
        response['lstFields'] << {'FieldID': 'Bor1.FNMACreditRefNo', 'Value': last_credit_report.credit_ref_number}
        response['lstFields'] << {'FieldID': 'Bor1.FMACCreditRefNo', 'Value': last_credit_report.credit_ref_number}
        found_credit_ref = true
      end
    end

    unless found_credit_ref
      response['lstFields'] << {'FieldID': 'Bor1.FNMACreditRefNo', 'Value': values['credit_ref_number'] || ''}
      response['lstFields'] << {'FieldID': 'Bor1.FMACCreditRefNo', 'Value': values['credit_ref_number'] || ''}
    end

    # response['borrower']['credit']['decision_score'] = values['decision_score'] || values['min_req_fico'] || 0
    # response['borrower']['credit']['auth_date'] = ( self.submitted_at)&.strftime('%Y-%m-%d')
    # response['borrower']['credit']['auth_method'] = value_is_truthy(values['credit_auth_method']) ? values['credit_auth_method'] : 'Internet'
    # values['custom_4079'] = values['credit_auth_notes'] ? values['credit_auth_notes'] : ''
    #
    if values['job_title']
      response['lstFields'] << {'FieldID': 'Bor1Emp.Position', 'Value': values['job_title']}
    end

    # if values['lead_source']
    #   values['custom_2976'] = values['lead_source']
    # end
    #
    if values['borrower_previous_employer_name']
      response['lstFields'] << {'FieldID': 'Bor1.FormerEmployer.Name', 'Value': values['borrower_previous_employer_name']}
    end
    if values['borrower_previous_employer_address']
      response['lstFields'] << {'FieldID': 'Bor1.FormerEmployer.Street', 'Value': values['borrower_previous_employer_address']}
    end
    if values['borrower_previous_employer_city']
      response['lstFields'] << {'FieldID': 'Bor1.FormerEmployer.City', 'Value': values['borrower_previous_employer_city']}
    end
    if values['borrower_previous_employer_state']
      response['lstFields'] << {'FieldID': 'Bor1.FormerEmployer.State', 'Value': to_state_or_empty(values['borrower_previous_employer_state'])}
    end
    if values['borrower_previous_employer_zip']
      response['lstFields'] << {'FieldID': 'Bor1.FormerEmployer.Zip', 'Value': values['borrower_previous_employer_zip']}
    end
    if values['borrower_previous_employer_phone']
      response['lstFields'] << {'FieldID': 'Bor1.FormerEmployer.Phone', 'Value': values['borrower_previous_employer_phone']}
    end
    if values['borrower_previous_employer_position']
      response['lstFields'] << {'FieldID': 'Bor1.FormerEmployer.Position', 'Value': values['borrower_previous_employer_position']}
    end
    # if values['borrower_previous_employer_start_date']
    #   values['custom_FE0011'] = values['borrower_previous_employer_start_date']
    # end
    # if values['borrower_previous_employer_end_date']
    #   values['custom_FE0014'] = values['borrower_previous_employer_end_date']
    # end
    #
    # if values['down_payment_explanation']
    #   values['custom_191'] = values['down_payment_explanation']
    # end
    #
    # # co_borrower contact and identity info
    #
    if value_is_truthy(values['has_coborrower'])
      response['lstFields'] << {'FieldID': 'Bor2.FirstName', 'Value': values['coborrower_first_name'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2.MiddleName', 'Value': values['coborrower_middle_name'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2.LastName', 'Value': values['coborrower_last_name'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2.SSN', 'Value': values['coborrower_ssn'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2.DOB', 'Value': to_date_or_empty(values["coborrower_dob"])}
      # response['lstFields'] << {'FieldID': 'Bor2.WorkPhoneFormatted', 'Value': values['borrower_work_phone'].present? ? values['borrower_work_phone'].gsub(/\D/, '') : ''}
      response['lstFields'] << {'FieldID': 'Bor2.HomePhone', 'Value': values['coborrower_home_phone'].present? ? values['coborrower_home_phone'].gsub(/\D/, '') : ''}
      response['lstFields'] << {'FieldID': 'Bor2.MobilePhone', 'Value': values['coborrower_cell_phone'].present? ? values['coborrower_cell_phone'].gsub(/\D/, '') : ''}
      response['lstFields'] << {'FieldID': 'Bor2.MaritalStatus', 'Value': values['coborrower_marital_status'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2.Email', 'Value': values['coborrower_email'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2.MailingCity', 'Value': values['coborrower_mailing_city'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2.MailingStreet', 'Value': values['coborrower_mailing_address'] || ''}
      mailing_state = to_state_or_empty(values["coborrower_mailing_state"])
      response['lstFields'] << {'FieldID': 'Bor2.MailingState', 'Value': mailing_state}
      response['lstFields'] << {'FieldID': 'Bor2.MailingZip', 'Value': values['coborrower_mailing_zip'] || ''}

      #   # co-borrower eConsent
      #   if values['coborrower_econsent'].present?
      #     response['co_borrower']['econsent'] = {}
      #     co_econsent_accepted = value_is_truthy(values['coborrower_econsent'])
      #     response['co_borrower']['econsent']['accepted'] = co_econsent_accepted ? 1 : 0
      #     response['co_borrower']['econsent']['ip_address'] = self.submission_ip || ""
      #     response['co_borrower']['econsent']['user_agent'] = self.submission_agent || ""
      #     response['co_borrower']['econsent']['consent_date'] = "#{self.submitted_at}"
      #     accepted_text = co_econsent_accepted ? 'Accepted' : 'Rejected'
      #     response['co_borrower']['econsent']['comments'] = "#{accepted_text} from #{self.submission_ip} at #{self.submitted_at} using #{self.submission_agent}"
      #   end
      #
      #   # co-borrower employer
      response['lstFields'] << {'FieldID': 'Bor2Emp.Name', 'Value': values['coborrower_employer_name'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2Emp.Street', 'Value': values['coborrower_employer_address'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2Emp.City', 'Value': values['coborrower_employer_city'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2Emp.State', 'Value': to_state_or_empty(values['coborrower_employer_state'])}
      response['lstFields'] << {'FieldID': 'Bor2Emp.Zip', 'Value': values['coborrower_employer_zip'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2Emp.YearsOnJob', 'Value': to_int_or_empty(values['coborrower_employer_years'])}
      #   response['co_borrower']['company_info']['months'] = to_int_or_empty(values['coborrower_employer_months'])

      #   # co-borrower present address
      response['lstFields'] << {'FieldID': 'Bor2Res.Street', 'Value': values['coborrower_address'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2Res.City', 'Value': values['coborrower_city'] || ''}
      present_state = to_state_or_empty(values['coborrower_state'])
      response['lstFields'] << {'FieldID': 'Bor2Res.State', 'Value': present_state}
      response['lstFields'] << {'FieldID': 'Bor2Res.Zip', 'Value': values['coborrower_zip'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2Res.NoYears', 'Value': values['coborrower_property_years'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2Res.NoMonths', 'Value': values['coborrower_property_months'] || ''}
      response['lstFields'] << {'FieldID': 'Bor2Res.LivingStatus', 'Value': values['coborrower_property_own'] && value_is_truthy(values['coborrower_property_own']) ? 1 : 2}

      #   # co-borrower previous address
      #   response['co_borrower']['prev_address'] = {}
      #   response['co_borrower']['prev_address']['street'] = values['coborrower_prev_address'] || ''
      #   response['co_borrower']['prev_address']['city'] = values['coborrower_prev_city'] || ''
      #   response['co_borrower']['prev_address']['state'] = (
      #   if values['coborrower_prev_state'].present?
      #     values['coborrower_prev_state'].split(' - ').last.upcase
      #   else
      #     ''
      #   end)
      #   response['co_borrower']['prev_address']['zip'] = values['coborrower_prev_zip'] || ''
      #   response['co_borrower']['prev_address']['years'] = to_int_or_empty(values['coborrower_prev_property_years'])
      #   response['co_borrower']['prev_address']['months'] = to_int_or_empty(values['coborrower_prev_property_months'])
      #   response['co_borrower']['prev_address']['own_rent'] = values['coborrower_prev_property_own'] && value_is_truthy(values['coborrower_prev_property_own']) ? 'Own' : 'Rent'
      #
      #   # co-borrower credit
      if (value_is_truthy(values['credit_authorization']) && values['has_coborrower'] && value_is_truthy(values['has_coborrower']) && values['coborrower_credit_authorization'].blank?) || (values['coborrower_credit_authorization'] && value_is_truthy(values['coborrower_credit_authorization']))
        response['lstFields'] << {'FieldID': 'Bor2.OKToPullCredit', 'Value': value_is_truthy(values['credit_authorization']) ? 'Yes' : 'No'}
        response['lstFields'] << {'FieldID': 'Bor2.TransUnionScore', 'Value': values['coborrower_credit_transunion'] || values['min_req_fico'] || 0}
        response['lstFields'] << {'FieldID': 'Bor2.EquifaxScore', 'Value': values['coborrower_credit_equifax'] || values['min_req_fico'] || 0}
        response['lstFields'] << {'FieldID': 'Bor2.ExperianScore', 'Value': values['coborrower_credit_experian'] || values['min_req_fico'] || 0}
        found_credit_ref = false
        last_credit_report = credit_reports.last
        if last_credit_report.present?
          if last_credit_report.credit_ref_number.present?
            response['lstFields'] << {'FieldID': 'Bor2.FNMACreditRefNo', 'Value': last_credit_report.credit_ref_number}
            response['lstFields'] << {'FieldID': 'Bor2.FMACCreditRefNo', 'Value': last_credit_report.credit_ref_number}
            found_credit_ref = true
          end
        end

        unless found_credit_ref
          response['lstFields'] << {'FieldID': 'Bor2.FNMACreditRefNo', 'Value': values['credit_ref_number'] || ''}
          response['lstFields'] << {'FieldID': 'Bor2.FMACCreditRefNo', 'Value': values['credit_ref_number'] || ''}
        end

      end

      response['CoBorrIncome'] = {}
      if values['coborrower_monthly_income']
        response['CoBorrIncome']['Base'] = values['coborrower_monthly_income'] || 0
      end
      if values['coborrower_bonuses']
        response['CoBorrIncome']['Bonus'] = values['coborrower_bonuses'] || 0
      end
      if values['coborrower_commission']
        response['CoBorrIncome']['Commission'] = values['coborrower_commission'] || 0
      end
      if values['coborrower_other_income']
        response['CoBorrIncome']['Other'] = values['coborrower_other_income'] || 0
      end

      #   values['custom_4007'] = values['coborrower_suffix'] || ''
        if values.key?('coborrower_is_self_employed')
          response['lstFields'] << {'FieldID': 'Bor2Emp.SelfEmp', 'Value': boolean_to_true_false(values['coborrower_is_self_employed'])}
        end
      #
        if values.key?('coborrower_has_outstanding_judgements')
          response['lstFields'] << {'FieldID': 'Bor2.OustandingJudgements', 'Value': boolean_to_yes_no(values['coborrower_has_outstanding_judgements'])}
        end
        if values.key?('coborrower_has_bankruptcy')
          response['lstFields'] << {'FieldID': 'Bor2.Bankruptcy', 'Value': boolean_to_yes_no(values['coborrower_has_bankruptcy'])}
        end
        if values.key?('coborrower_has_foreclosure')
          response['lstFields'] << {'FieldID': 'Bor2.PropertyForeclosed', 'Value': boolean_to_yes_no(values['coborrower_has_foreclosure'])}
        end
        if values.key?('coborrower_party_to_lawsuit')
          response['lstFields'] << {'FieldID': 'Bor2.PartyToLawsuit', 'Value': boolean_to_yes_no(values['coborrower_party_to_lawsuit'])}
        end
        if values.key?('coborrower_has_obligations')
          response['lstFields'] << {'FieldID': 'Bor2.LoanForeclosed', 'Value': boolean_to_yes_no(values['coborrower_has_obligations'])}
        end
        if values.key?('coborrower_has_delinquent_debt')
          response['lstFields'] << {'FieldID': 'Bor2.DelinquentFederalDebt', 'Value': boolean_to_yes_no(values['coborrower_has_delinquent_debt'])}
        end
        if values.key?('coborrower_has_alimony')
          response['lstFields'] << {'FieldID': 'Bor2.AlimonyObligation', 'Value': boolean_to_yes_no(values['coborrower_has_alimony'])}
          values['custom_179'] = boolean_to_y_n(values['coborrower_has_alimony'])
        end
        if values.key?('coborrower_is_comaker_or_endorser')
          response['lstFields'] << {'FieldID': 'Bor2.EndorserOnNote', 'Value': boolean_to_yes_no(values['coborrower_is_comaker_or_endorser'])}
        end
        if values.key?('coborrower_is_primary_residence')
          response['lstFields'] << {'FieldID': 'Bor2.OccupyAsPrimaryRes', 'Value': boolean_to_yes_no(values['coborrower_is_primary_residence'])}
          values['custom_1343'] = boolean_to_yes_no(values['coborrower_is_primary_residence'])
        end
        if values.key?('coborrower_down_payment_borrowed')
          response['lstFields'] << {'FieldID': 'Bor2.DownPaymentBorrowed', 'Value': boolean_to_yes_no(values['coborrower_down_payment_borrowed'])}
        end

        if values.key?('coborrower_is_us_citizen')
          us_citizen = value_is_truthy(values['coborrower_is_us_citizen'])
          response['lstFields'] << {'FieldID': 'Bor2.CitizenResidencyType', 'Value': us_citizen ? 1 : 0}

          unless us_citizen
            if values.key?('coborrower_is_permanent_resident')
              response['lstFields'] << {'FieldID': 'Bor2.CitizenResidencyType', 'Value': value_is_truthy(values['coborrower_is_permanent_resident']) ? 2 : 0}
            end
          end
        end

        if value_is_truthy(values['coborrower_has_ownership_interest'])
          response['lstFields'] << {'FieldID': 'Bor2.OwnershipInterest', 'Value': boolean_to_yes_no(values['coborrower_has_ownership_interest'])}

          response['lstFields'] << {'FieldID': 'Bor2.PropertyType', 'Value': 0}
          if values['coborrower_previous_property_type_declaration'] == 'Primary Residence'
            response['lstFields'] << {'FieldID': 'Bor2.PropertyType', 'Value': 1}
          elsif values['coborrower_previous_property_type_declaration'] == 'Second Home'
            response['lstFields'] << {'FieldID': 'Bor2.PropertyType', 'Value': 2}
          elsif values['coborrower_previous_property_type_declaration'] == 'Investment Property'
            response['lstFields'] << {'FieldID': 'Bor2.PropertyType', 'Value': 3}
          end

          if values['coborrower_previous_property_title_declaration'] == 'Sole Ownership'
            response['lstFields'] << {'FieldID': 'Bor2.PropertyType', 'Value': 1}
          elsif values['coborrower_previous_property_title_declaration'] == 'Joint With Spouse'
            response['lstFields'] << {'FieldID': 'Bor2.PropertyType', 'Value': 2}
          elsif values['coborrower_previous_property_title_declaration'] == 'Joint With Other Than Spouse'
            response['lstFields'] << {'FieldID': 'Bor2.PropertyType', 'Value': 3}
          end

        end

      response['CoBorrAssets'] = []
      if values['coborrower_checking_account']
        response['CoBorrAssets'] << {'BankName': 'Checking', 'CheckingAmt': values['coborrower_checking_account']}
      end
      if values['coborrower_savings_account']
        response['CoBorrAssets'] << {'BankName': 'Savings', 'SavingAmt': values['coborrower_savings_account']}
      end
      if values['coborrower_assets_other']
        response['CoBorrAssets'] << {'BankName': 'Other Assets', 'OtherAmt': values['coborrower_assets_other']}
      end
      if values['coborrower_assets_gift_funds']
        response['CoBorrAssets'] << {'BankName': 'Gift', 'GiftAmt': values['coborrower_assets_gift_funds']}
      end
      if values['coborrower_assets_retirement']
        response['CoBorrAssets'] << {'BankName': 'Retirement', 'RetirementAmt': values['coborrower_assets_retirement']}
      end

      if has_hmda
          if value_is_truthy(values['coborrower_provide_demographics'])

            if values['coborrower_demographics_method']
              case values['coborrower_demographics_method']
                when 'Face-to-face'
                  response['lstFields'] << {'FieldID': 'Bor2.DemographicInfoProvidedMethod', 'Value': 1}
                when 'Telephone Interview'
                  response['lstFields'] << {'FieldID': 'Bor2.DemographicInfoProvidedMethod', 'Value': 2}
                when 'Fax or Mail'
                  response['lstFields'] << {'FieldID': 'Bor2.DemographicInfoProvidedMethod', 'Value': 3}
                else
                  response['lstFields'] << {'FieldID': 'Bor2.DemographicInfoProvidedMethod', 'Value': 4}
              end

              if values['coborrower_ethnicity_method'] == 'Face-to-face'
                case values['ethnicity_method']
                  when 'Visual Observation'
                    response['lstFields'] << {'FieldID': 'Bor2.DemographicInfoProvidedMethod', 'Value': 3}
                  else
                    response['lstFields'] << {'FieldID': 'Bor2.DemographicInfoProvidedMethod', 'Value': 1}
                end

                case values['coborrower_race_method']
                  when 'Visual Observation'
                    response['lstFields'] << {'FieldID': 'Bor2.Race2CompletionMethod', 'Value': 3}
                  else
                    response['lstFields'] << {'FieldID': 'Bor2.Race2CompletionMethod', 'Value': 1}
                end

                case values['coborrower_sex_method']
                  when 'Visual Observation'
                    response['lstFields'] << {'FieldID': 'Bor2.Gender2CompletionMethod', 'Value': 3}
                  else
                    response['lstFields'] << {'FieldID': 'Bor2.Gender2CompletionMethod', 'Value': 1}
                end
              end

              case values['coborrower_ethnicity']
                when 'Hispanic or Latino'
                  response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2HispanicOrLatino', 'Value': true}
                when 'Not Hispanic or Latino'
                  response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2NotHispanicOrLatino', 'Value': true}
                when 'I do not wish to provide this information'
                  response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2IDoNotWishToFurnish', 'Value': true}
              end


              if values['coborrower_ethnicity'] == 'Hispanic or Latino'
                case values['coborrower_ethnicity_latino']
                  when 'Mexican'
                    response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2Mexican', 'Value': true}
                  when 'Puerto Rican'
                    response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2PuertoRican', 'Value': true}
                  when 'Cuban'
                    response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2Cuban', 'Value': true}
                  when 'Other Hispanic or Latino'
                    response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2OtherHispanicOrLatino', 'Value': true}
                    response['lstFields'] << {'FieldID': 'Bor2.EthnicityOtherHispanicOrLatinoDesc', 'Value': values['coborrower_other_hispanic_or_latino_origin']}
                  else
                    response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2OtherHispanicOrLatino', 'Value': true}
                    response['lstFields'] << {'FieldID': 'Bor2.EthnicityOtherHispanicOrLatinoDesc', 'Value': values['coborrower_other_hispanic_or_latino_origin']}
                end
              elsif values['coborrower_ethnicity'] == 'Not Hispanic or Latino'
                response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2NotHispanicOrLatino', 'Value': true}
              elsif values['coborrower_ethnicity'] == 'I do not wish to provide this information'
                response['lstFields'] << {'FieldID': 'Bor2.Ethnicity2IDoNotWishToFurnish', 'Value': true}
              end


              case values['coborrower_race']
                when 'American Indian or Alaska Native'
                  response['lstFields'] << {'FieldID': 'Bor2.Race2AmericanIndian', 'Value': true}
                  response['lstFields'] << {'FieldID': 'Bor2.RaceAmericanIndianTribe', 'Value': values['coborrower_race_american_indian_other']}
                when 'Asian'
                  response['lstFields'] << {'FieldID': 'Bor2.Race2Asian', 'Value': true}
                  case values ['coborrower_race_asian']
                    when 'Asian Indian'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2AsianIndian', 'Value': true}
                    when 'Chinese'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2Chinese', 'Value': true}
                    when 'Filipino'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2Filipino', 'Value': true}
                    when 'Japanese'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2Japanese', 'Value': true}
                    when 'Korean'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2Korean', 'Value': true}
                    when 'Vietnamese'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2Vietnamese', 'Value': true}
                    when 'Other Asian'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2OtherAsian', 'Value': true}
                      response['lstFields'] << {'FieldID': 'Bor2.RaceOtherAsianDesc', 'Value': values['coborrower_asian_origin_other']}
                    else
                      response['lstFields'] << {'FieldID': 'Bor2.Race2OtherAsian', 'Value': true}
                      response['lstFields'] << {'FieldID': 'Bor2.RaceOtherAsianDesc', 'Value': values['coborrower_asian_origin_other']}
                  end
                when 'Black or African American'
                  response['lstFields'] << {'FieldID': 'Bor2.Race2Black', 'Value': true}
                when 'Native Hawaiian or Other Pacific Islander'
                  response['lstFields'] << {'FieldID': 'Bor2.Race2PacificIslander', 'Value': true}
                  case values ['pacific_islander']
                    when 'Native Hawaiian'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2NativeHawaiian', 'Value': true}
                    when 'Guamanian or Chamorro'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2GuamanianOrChamorro', 'Value': true}
                    when 'Samoan'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2Samoan', 'Value': true}
                    when 'Other Pacific Islander'
                      response['lstFields'] << {'FieldID': 'Bor2.Race2OtherPacificIslander', 'Value': true}
                      response['lstFields'] << {'FieldID': 'Bor2.RaceOtherPacificIslanderDesc', 'Value': values['coborrower_pacific_islander_other']}
                    else
                      response['lstFields'] << {'FieldID': 'Bor2.Race2OtherPacificIslander', 'Value': true}
                      response['lstFields'] << {'FieldID': 'Bor2.RaceOtherPacificIslanderDesc', 'Value': values['coborrower_pacific_islander_other']}
                  end
                when 'White'
                  response['lstFields'] << {'FieldID': 'Bor2.Race2White', 'Value': true}
                when 'I do not wish to provide this information'
                  response['lstFields'] << {'FieldID': 'Bor2.Race2IDoNotWishToFurnish', 'Value': true}
                else
                  response['lstFields'] << {'FieldID': 'Bor2.Race2IDoNotWishToFurnish', 'Value': true}
              end

              case values['coborrower_sex']
                when 'Male'
                  response['lstFields'] << {'FieldID': 'Bor2.Gender2Male', 'Value': true}
                when 'Female'
                  response['lstFields'] << {'FieldID': 'Bor2.Gender2Female', 'Value': true}
                when 'I do not wish to provide this information'
                  response['lstFields'] << {'FieldID': 'Bor2.Gender2IDoNotWishToFurnish', 'Value': true}
              end
            end
          else
            response['lstFields'] << {'FieldID': 'Bor2.GMINotApplicable', 'Value': true}
          end
        else
          if value_is_truthy(values['coborrower_provide_demographics'])
            case values['coborrower_ethnicity']
              when "Hispanic or Latino"
                response['lstFields'] << {'FieldID': 'Bor2.Ethnicity', 'Value': 1}
              when "Not Hispanic or Latino"
                response['lstFields'] << {'FieldID': 'Bor2.Ethnicity', 'Value': 2}
              when "I do not wish to provide this information"
                response['lstFields'] << {'FieldID': 'Bor2.Ethnicity', 'Value': 3}
              else
                response['lstFields'] << {'FieldID': 'Bor2.Ethnicity', 'Value': 0}
            end
            if values['coborrower_race']
              case values['coborrower_race']
                when "American Indian or Alaska Native"
                  response['lstFields'] << {'FieldID': 'Bor2.RaceAmericanIndian', 'Value': true}
                when "Asian"
                  response['lstFields'] << {'FieldID': 'Bor2.RaceAsian', 'Value': true}
                when "Black or African American"
                  response['lstFields'] << {'FieldID': 'Bor2.RaceBlack', 'Value': true}
                when "Native Hawaiian"
                  response['lstFields'] << {'FieldID': 'Bor2.RacePacificIslander', 'Value': true}
                when "White"
                  response['lstFields'] << {'FieldID': 'Bor2.RaceWhite', 'Value': true}
                when "Information not provided"
                  response['lstFields'] << {'FieldID': 'Bor2.RaceNotProvided', 'Value': true}
                else
                  response['lstFields'] << {'FieldID': 'Bor2.RaceNotApplicable', 'Value': true}
              end
            end

            if values['coborrower_gender'] == 'Male'
              response['lstFields'] << {'FieldID': 'Bor2.Gender', 'Value': 2}
            elsif values['coborrower_gender'] == 'Female'
              response['lstFields'] << {'FieldID': 'Bor2.Gender', 'Value': 1}
            end
          else
            response['lstFields'] << {'FieldID': 'Bor2.GovDoNotWishToFurnish', 'Value': true}
          end
        end


    end # ends has_co_borrower check
    #
    # # subject property
    # response['property'] = {}
    response['lstFields'] << {'FieldID': 'SubProp.Street', 'Value': values['property_street'] || ''}
    response['lstFields'] << {'FieldID': 'SubProp.City', 'Value': values['property_city'] || ''}

    response['lstFields'] << {'FieldID': 'SubProp.State', 'Value': property_state}
    response['lstFields'] << {'FieldID': 'SubProp.Zip', 'Value': values['property_zip'] || ''}
    response['lstFields'] << {'FieldID': 'SubProp.AppraisedValue', 'Value': values['property_appraised_value'] || ''}
    response['lstFields'] << {'FieldID': 'SubProp.AssessedValue', 'Value': values['property_est_value'] || ''}

    # # main loan info on application
    # response['loan'] = {}

    purch_price = values['purchase_price'].present? ? fix_num(values['purchase_price']).to_f : 0.0
    response['lstFields'] << {'FieldID': 'Loan.PurPrice', 'Value': purch_price}
    down_pmt_pct = values['down_payment_pct'].present? ? fix_num(values['down_payment_pct']).to_f : 0.0
    down_pmt_amt = purch_price - (purch_price * down_pmt_pct)
    response['lstFields'] << {'FieldID': 'FileData.DownPaymentAmount1', 'Value': down_pmt_amt}
    response['lstFields'] << {'FieldID': 'Loan.BaseLoan', 'Value': fix_num( values['loan_amount'] ) || 0}

    if values['loan_type']
      case values ['loan_type']
        when 'Conventional'
          response['lstFields'] << {'FieldID': 'Loan.MortgageType', 'Value': 3}
        when 'VA'
          response['lstFields'] << {'FieldID': 'Loan.MortgageType', 'Value': 1}
        when 'FHA'
          response['lstFields'] << {'FieldID': 'Loan.MortgageType', 'Value': 2}
        when 'Other'
          response['lstFields'] << {'FieldID': 'Loan.MortgageType', 'Value': 5}
        when 'USDA-RHS'
          response['lstFields'] << {'FieldID': 'Loan.MortgageType', 'Value': 4}
        when 'HELOC'
          response['lstFields'] << {'FieldID': 'Loan.MortgageType', 'Value': 6}
        else
          response['lstFields'] << {'FieldID': 'Loan.MortgageType', 'Value': 0}
      end
    end

    # response['loan']['est_closing_date'] = ''
    response['lstFields'] << {'FieldID': 'Loan.Term', 'Value': values['loan_term'] || 0}

    if values['loan_purpose']
      case values ['loan_purpose']
        when 'Refinance' || 'No Cash-Out Refinance' || 'Cash-Out Refinance'
          response['lstFields'] << {'FieldID': 'Loan.LoanPurpose', 'Value': 2}
          if values['current_lien']
            response['lstFields'] << {'FieldID': 'SubProp.RAmtExLiens', 'Value': values['current_lien']}
          end
        when 'Construction'
          response['lstFields'] << {'FieldID': 'Loan.LoanPurpose', 'Value': 3}
          if values['current_lien']
            response['lstFields'] << {'FieldID': 'SubProp.CAmtExLiens', 'Value': values['current_lien']}
          end
        else
          response['lstFields'] << {'FieldID': 'Loan.LoanPurpose', 'Value': 1}
      end
    end

    response['lstFields'] << {'FieldID': 'Loan.AmortizationType', 'Value': 1}
    # response['lstFields'] << {'FieldID': 'Status.ApplicationDate', 'Value': "#{self.submitted_at}"}

    if values['current_expense_tax']
      response['lstFields'] << {'FieldID': 'Application.PresentTaxes', 'Value': values['current_expense_tax']}
    end

    if values['current_expense_hazard_ins']
      response['lstFields'] << {'FieldID': 'Application.PresentHazardIns', 'Value': values['current_expense_hazard_ins']}
    end

    response['BorrAssets'] = []
    unless values['checking_account'].blank?
      response['BorrAssets'] << {'BankName': 'Checking', 'CheckingAmt': values['checking_account']}
    end
    unless values['savings_account'].blank?
      response['BorrAssets'] << {'BankName': 'Savings', 'SavingAmt': values['savings_account']}
    end
    unless values['assets_other'].blank?
      response['BorrAssets'] << {'BankName': 'Other Assets', 'OtherAmt': values['assets_other']}
    end
    unless values['assets_gift_funds'].blank?
      response['BorrAssets'] << {'BankName': 'Gift', 'GiftAmt': values['assets_gift_funds']}
    end
    unless values['assets_retirement'].blank?
      response['BorrAssets'] << {'BankName': 'Retirement', 'RetirementAmt': values['assets_retirement']}
    end

    if values.key?('is_down_payment_borrowed')
      response['lstFields'] << {'FieldID': 'Bor1.DownPaymentBorrowed', 'Value': boolean_to_yes_no(values['is_down_payment_borrowed'])}
    end

    if has_hmda
      if value_is_truthy(values['provide_demographics'])

        if values['demographics_method']
          case values['demographics_method']
            when 'Face-to-face'
              response['lstFields'] << {'FieldID': 'Bor1.DemographicInfoProvidedMethod', 'Value': 1}
            when 'Telephone Interview'
              response['lstFields'] << {'FieldID': 'Bor1.DemographicInfoProvidedMethod', 'Value': 2}
            when 'Fax or Mail'
              response['lstFields'] << {'FieldID': 'Bor1.DemographicInfoProvidedMethod', 'Value': 3}
            else
              response['lstFields'] << {'FieldID': 'Bor1.DemographicInfoProvidedMethod', 'Value': 4}
          end

          if values['ethnicity_method'] == 'Face-to-face'
            case values['ethnicity_method']
              when 'Visual Observation'
                response['lstFields'] << {'FieldID': 'Bor1.DemographicInfoProvidedMethod', 'Value': 3}
              else
                response['lstFields'] << {'FieldID': 'Bor1.DemographicInfoProvidedMethod', 'Value': 1}
            end

            case values['race_method']
              when 'Visual Observation'
                response['lstFields'] << {'FieldID': 'Bor1.Race2CompletionMethod', 'Value': 3}
              else
                response['lstFields'] << {'FieldID': 'Bor1.Race2CompletionMethod', 'Value': 1}
            end

            case values['sex_method']
              when 'Visual Observation'
                response['lstFields'] << {'FieldID': 'Bor1.Gender2CompletionMethod', 'Value': 3}
              else
                response['lstFields'] << {'FieldID': 'Bor1.Gender2CompletionMethod', 'Value': 1}
            end
          end

          case values['ethnicity']
            when 'Hispanic or Latino'
              response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2HispanicOrLatino', 'Value': true}
            when 'Not Hispanic or Latino'
              response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2NotHispanicOrLatino', 'Value': true}
            when 'I do not wish to provide this information'
              response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2IDoNotWishToFurnish', 'Value': true}
          end


          if values['ethnicity'] == 'Hispanic or Latino'
            case values['ethnicity_latino']
              when 'Mexican'
                response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2Mexican', 'Value': true}
              when 'Puerto Rican'
                response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2PuertoRican', 'Value': true}
              when 'Cuban'
                response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2Cuban', 'Value': true}
              when 'Other Hispanic or Latino'
                response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2OtherHispanicOrLatino', 'Value': true}
                response['lstFields'] << {'FieldID': 'Bor1.EthnicityOtherHispanicOrLatinoDesc', 'Value': values['other_hispanic_or_latino_origin']}
              else
                response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2OtherHispanicOrLatino', 'Value': true}
                response['lstFields'] << {'FieldID': 'Bor1.EthnicityOtherHispanicOrLatinoDesc', 'Value': values['other_hispanic_or_latino_origin']}
            end
          elsif values['ethnicity'] == 'Not Hispanic or Latino'
            response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2NotHispanicOrLatino', 'Value': true}
          elsif values['ethnicity'] == 'I do not wish to provide this information'
            response['lstFields'] << {'FieldID': 'Bor1.Ethnicity2IDoNotWishToFurnish', 'Value': true}
          end


          case values['race']
            when 'American Indian or Alaska Native'
              response['lstFields'] << {'FieldID': 'Bor1.Race2AmericanIndian', 'Value': true}
              response['lstFields'] << {'FieldID': 'Bor1.RaceAmericanIndianTribe', 'Value': values['race_american_indian_other']}
            when 'Asian'
              response['lstFields'] << {'FieldID': 'Bor1.Race2Asian', 'Value': true}
              case values ['race_asian']
                when 'Asian Indian'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2AsianIndian', 'Value': true}
                when 'Chinese'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2Chinese', 'Value': true}
                when 'Filipino'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2Filipino', 'Value': true}
                when 'Japanese'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2Japanese', 'Value': true}
                when 'Korean'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2Korean', 'Value': true}
                when 'Vietnamese'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2Vietnamese', 'Value': true}
                when 'Other Asian'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2OtherAsian', 'Value': true}
                  response['lstFields'] << {'FieldID': 'Bor1.RaceOtherAsianDesc', 'Value': values['asian_origin_other']}
                else
                  response['lstFields'] << {'FieldID': 'Bor1.Race2OtherAsian', 'Value': true}
                  response['lstFields'] << {'FieldID': 'Bor1.RaceOtherAsianDesc', 'Value': values['asian_origin_other']}
              end
            when 'Black or African American'
              response['lstFields'] << {'FieldID': 'Bor1.Race2Black', 'Value': true}
            when 'Native Hawaiian or Other Pacific Islander'
              response['lstFields'] << {'FieldID': 'Bor1.Race2PacificIslander', 'Value': true}
              case values ['pacific_islander']
                when 'Native Hawaiian'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2NativeHawaiian', 'Value': true}
                when 'Guamanian or Chamorro'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2GuamanianOrChamorro', 'Value': true}
                when 'Samoan'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2Samoan', 'Value': true}
                when 'Other Pacific Islander'
                  response['lstFields'] << {'FieldID': 'Bor1.Race2OtherPacificIslander', 'Value': true}
                  response['lstFields'] << {'FieldID': 'Bor1.RaceOtherPacificIslanderDesc', 'Value': values['pacific_islander_other']}
                else
                  response['lstFields'] << {'FieldID': 'Bor1.Race2OtherPacificIslander', 'Value': true}
                  response['lstFields'] << {'FieldID': 'Bor1.RaceOtherPacificIslanderDesc', 'Value': values['pacific_islander_other']}
              end
            when 'White'
              response['lstFields'] << {'FieldID': 'Bor1.Race2White', 'Value': true}
            when 'I do not wish to provide this information'
              response['lstFields'] << {'FieldID': 'Bor1.Race2IDoNotWishToFurnish', 'Value': true}
            else
              response['lstFields'] << {'FieldID': 'Bor1.Race2IDoNotWishToFurnish', 'Value': true}
          end

          case values['sex']
            when 'Male'
              response['lstFields'] << {'FieldID': 'Bor1.Gender2Male', 'Value': true}
            when 'Female'
              response['lstFields'] << {'FieldID': 'Bor1.Gender2Female', 'Value': true}
            when 'I do not wish to provide this information'
              response['lstFields'] << {'FieldID': 'Bor1.Gender2IDoNotWishToFurnish', 'Value': true}
          end
        end
      else
        response['lstFields'] << {'FieldID': 'Bor1.GovDoNotWishToFurnish', 'Value': true}
      end
    else
      if value_is_truthy(values['provide_demographics'])
        case values['ethnicity']
          when "Hispanic or Latino"
            response['lstFields'] << {'FieldID': 'Bor1.Ethnicity', 'Value': 1}
          when "Not Hispanic or Latino"
            response['lstFields'] << {'FieldID': 'Bor1.Ethnicity', 'Value': 2}
          when "I do not wish to provide this information"
            response['lstFields'] << {'FieldID': 'Bor1.Ethnicity', 'Value': 3}
          else
            response['lstFields'] << {'FieldID': 'Bor1.Ethnicity', 'Value': 0}
        end
        if values['race']
          case values['race']
            when "American Indian or Alaska Native"
              response['lstFields'] << {'FieldID': 'Bor1.RaceAmericanIndian', 'Value': true}
            when "Asian"
              response['lstFields'] << {'FieldID': 'Bor1.RaceAsian', 'Value': true}
            when "Black or African American"
              response['lstFields'] << {'FieldID': 'Bor1.RaceBlack', 'Value': true}
            when "Native Hawaiian"
              response['lstFields'] << {'FieldID': 'Bor1.RacePacificIslander', 'Value': true}
            when "White"
              response['lstFields'] << {'FieldID': 'Bor1.RaceWhite', 'Value': true}
            when "Information not provided"
              response['lstFields'] << {'FieldID': 'Bor1.RaceNotProvided', 'Value': true}
            else
              response['lstFields'] << {'FieldID': 'Bor1.RaceNotApplicable', 'Value': true}
          end
        end

        if values['gender'] == 'Male'
          response['lstFields'] << {'FieldID': 'Bor1.Gender', 'Value': 2}
        elsif values['gender'] == 'Female'
          response['lstFields'] << {'FieldID': 'Bor1.Gender', 'Value': 1}
        end
      else
        response['lstFields'] << {'FieldID': 'Bor1.GovDoNotWishToFurnish', 'Value': true}
      end
    end

    if values['property_type']
      if values['property_type'] == 'Single Family'
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 1}
      elsif values['property_type'] == 'Condo'
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 3}
      elsif values['property_type'] == 'Multi-Unit Property'
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 2}
      elsif values['property_type'] == 'Townhome'
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 5}
      elsif values['property_type'] == 'Detached Condo'
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 5}
      elsif values['property_type'] == 'PUD'
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 6}
      elsif values['property_type'] == 'Cooperative'
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 7}
      elsif values['property_type'] == 'Manufactured Home'
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 8}
      else
        response['lstFields'] << {'FieldID': 'SubProp.PropertyType', 'Value': 1}
      end
    end

    if values['occupancy_type']
      if values['occupancy_type'] == 'Non-Owner Occupied'
        response['lstFields'] << {'FieldID': 'FileData.OccupancyType', 'Value': 3}
      else
        response['lstFields'] << {'FieldID': 'FileData.OccupancyType', 'Value': 1}
      end
    end

    response['BorrIncome'] = {}
    if values['monthly_income']
      response['BorrIncome']['Base'] = values['monthly_income'] || 0
    end
    if values['bonuses']
      response['BorrIncome']['Bonus'] = values['bonuses'] || 0
    end
    if values['commission']
      response['BorrIncome']['Commission'] = values['commission'] || 0
    end
    if values['other_income']
      response['BorrIncome']['Other'] = values['other_income'] || 0
    end

    response['lstFields'] << {'FieldID': 'Bor1.NoDeps', 'Value': values['number_dependents'] || 0}
    response['lstFields'] << {'FieldID': 'Bor1.DepsAges', 'Value': values['dependents_age'] || 0}

    if values.key?('is_self_employed')
      response['lstFields'] << {'FieldID': 'Employer.SelfEmp', 'Value': value_is_truthy(values['is_self_employed'])}
    end
    #

    if values.key?('has_outstanding_judgements')
      response['lstFields'] << {'FieldID': 'Bor1.OustandingJudgements', 'Value': boolean_to_yes_no(values['has_outstanding_judgements'])}
    end
    if values.key?('has_bankruptcy')
      response['lstFields'] << {'FieldID': 'Bor1.Bankruptcy', 'Value': boolean_to_yes_no(values['has_bankruptcy'])}
    end
    if values.key?('has_foreclosure')
      response['lstFields'] << {'FieldID': 'Bor1.PropertyForeclosed', 'Value': boolean_to_yes_no(values['has_foreclosure'])}
    end
    if values.key?('party_to_lawsuit')
      response['lstFields'] << {'FieldID': 'Bor1.PartyToLawsuit', 'Value': boolean_to_yes_no(values['party_to_lawsuit'])}
    end
    if values.key?('has_obligations')
      response['lstFields'] << {'FieldID': 'Bor1.LoanForeclosed', 'Value': boolean_to_yes_no(values['has_obligations'])}
    end
    if values.key?('has_delinquent_debt')
      response['lstFields'] << {'FieldID': 'Bor1.DelinquentFederalDebt', 'Value': boolean_to_yes_no(values['has_delinquent_debt'])}
    end
    if values.key?('has_alimony')
      response['lstFields'] << {'FieldID': 'Bor1.AlimonyObligation', 'Value': boolean_to_yes_no(values['has_alimony'])}
      values['custom_179'] = boolean_to_y_n(values['has_alimony'])
    end
    if values.key?('is_comaker_or_endorser')
      response['lstFields'] << {'FieldID': 'Bor1.EndorserOnNote', 'Value': boolean_to_yes_no(values['is_comaker_or_endorser'])}
    end
    if values.key?('is_primary_residence')
      response['lstFields'] << {'FieldID': 'Bor1.OccupyAsPrimaryRes', 'Value': boolean_to_yes_no(values['is_primary_residence'])}
      values['custom_1343'] = boolean_to_yes_no(values['is_primary_residence'])
    end
    if values.key?('down_payment_borrowed')
      response['lstFields'] << {'FieldID': 'Bor1.DownPaymentBorrowed', 'Value': boolean_to_yes_no(values['down_payment_borrowed'])}
    end

    if values.key?('is_us_citizen')
      us_citizen = value_is_truthy(values['is_us_citizen'])
      response['lstFields'] << {'FieldID': 'Bor1.CitizenResidencyType', 'Value': us_citizen ? 1 : 0}

      unless us_citizen
        if values.key?('is_permanent_resident')
          response['lstFields'] << {'FieldID': 'Bor1.CitizenResidencyType', 'Value': value_is_truthy(values['is_permanent_resident']) ? 2 : 0}
        end
      end
    end

    if value_is_truthy(values['has_ownership_interest'])
      response['lstFields'] << {'FieldID': 'Bor1.OwnershipInterest', 'Value': boolean_to_yes_no(values['has_ownership_interest'])}

      response['lstFields'] << {'FieldID': 'Bor1.PropertyType', 'Value': 0}
      if values['previous_property_type_declaration'] == 'Primary Residence'
        response['lstFields'] << {'FieldID': 'Bor1.PropertyType', 'Value': 1}
      elsif values['previous_property_type_declaration'] == 'Second Home'
        response['lstFields'] << {'FieldID': 'Bor1.PropertyType', 'Value': 2}
      elsif values['previous_property_type_declaration'] == 'Investment Property'
        response['lstFields'] << {'FieldID': 'Bor1.PropertyType', 'Value': 3}
      end

      if values['previous_property_title_declaration'] == 'Sole Ownership'
        response['lstFields'] << {'FieldID': 'Bor1.PropertyType', 'Value': 1}
      elsif values['previous_property_title_declaration'] == 'Joint With Spouse'
        response['lstFields'] << {'FieldID': 'Bor1.PropertyType', 'Value': 2}
      elsif values['previous_property_title_declaration'] == 'Joint With Other Than Spouse'
        response['lstFields'] << {'FieldID': 'Bor1.PropertyType', 'Value': 3}
      end

    end

    if values.key?('is_firsttimer')
      response['lstFields'] << {'FieldID': 'Bor1.FirstTimeHomebuyer', 'Value': value_is_truthy(values['is_firsttimer'])}
    end

    unless values['custom_1811']
      if values['type_of_property']
        if values['type_of_property'] == 'Primary Residence'
          response['lstFields'] << {'FieldID': 'Bor1.FirstTimeHomebuyer', 'Value': 1}
        elsif values['type_of_property'] == 'Secondary Residence'
          response['lstFields'] << {'FieldID': 'Bor1.FirstTimeHomebuyer', 'Value': 2}
        else
          response['lstFields'] << {'FieldID': 'Bor1.FirstTimeHomebuyer', 'Value': 3}
        end
      end
    end

    if company_id == 111305 # Residential Bancorp
      response['lstFields'] << {'FieldID': 'ExtendedFields.Status_ApplicationFromApp', 'Value': 'true'}
    end

    response
  end


  def get_field_description(key, field_arr)
    if !@field_mappings.present?
      @field_mappings = LosFieldMapping.all.map{|m| [m.los_key,m]}.to_h
    end

    desc_response = ''
    description_idx = field_arr.find_index { |item| item['key'] && item['key'] == key }
    if description_idx.nil?
      field_mapping = @field_mappings[key]
      if field_mapping&.question
        desc_response = field_mapping.question
      else
        desc_response = "Field #{key}"
      end
    else
      desc_response = field_arr[description_idx]['title']
    end

    desc_response
  end

  def to_state_or_empty(value)
    if value.present?
      state = value.strip
      if state.index(' - ')
        state.split(' - ').last.upcase
      elsif state.length > 2
        StateHelper.code_for_state(state) || ""
      elsif state.length == 2
        state.upcase
      else
        ""
      end
    else
      ""
    end

  end

  def to_date_or_empty(value,format = '%Y-%m-%d')
    if value.present?
      date = Chronic.parse(value)
      if date
        return date.strftime(format)
      end
    end

    return ""
  end

  def to_int_or_empty(value)
    if value.present?
      return value.to_i
    else
      return ''
    end
  end

  def value_is_truthy(value)
    truthy_values.include? value
  end

  def truthy_values
    ["1", 1, "true", "True", "TRUE", true, "Y", "y", "yes", "Yes", "YES"]
  end

  def boolean_to_y_n(value)
    if value_is_truthy(value)
      return "Y"
    else
      return "N"
    end
  end

  def boolean_to_true_false(value)
    if value_is_truthy(value)
      return 'true'
    else
      return 'false'
    end
  end

  def boolean_to_yes_no(value)
    if value_is_truthy(value)
      return "Yes"
    else
      return "No"
    end
  end

  def fix_num number
    number.present? ? number.to_s.gsub( /[^0-9\.]/,'') : number
  end

  def update_structure
    if self.app_user
      sp = self.app_user.servicer_profile
    elsif self.servicer_profile
      sp = self.servicer_profile
    end
    if sp.present?
      json = JSON.parse(self.loan_app_json)
      original_loan_app = JSON.parse(sp.effective_form_def( :loan_app ))
      json["structure"] = original_loan_app["structure"]
      if json["structure"][0].is_a?(Array)
      # if original_loan_app["structure"][0].is_a?(Array)
      #   if self.phases_complete_changed?
      #     phase = self.phases_complete_was
      #   else
      #     phase = self.phases_complete
      #   end
      #   original_loan_app["structure"][phase] = json["structure"]
      #   json["structure"] = original_loan_app["structure"]
        total_phases = json["structure"].size
      elsif json["structure"][0].is_a?(Hash)
        total_phases = 1
      end
      self.total_phases = total_phases
      self.loan_app_json = json.to_json
    end
  end

  def update_consent_documents(phase)
    fields_in_phase = fields_in_phase(phase)
    econsent_fields = econsent_fields_lookup
    credit_auth_fields = credit_auth_field_lookup

    if (self.app_user&.servicer_profile&.company&.generate_econsent_form || self.servicer_profile&.company&.generate_econsent_form) && econsent_fields[:borrower].present? && fields_in_phase.include?(econsent_fields[:borrower]["key"])
      GenerateEconsentDocJob.perform_later( :user_loan_app_id => self.id )
    end #end only generating for companies with the option enabled


    if (self.app_user&.servicer_profile&.company&.generate_credit_auth_form || self.servicer_profile&.company&.generate_credit_auth_form) && credit_auth_fields[:borrower].present? && fields_in_phase.include?(credit_auth_fields[:borrower]["key"])
      GenerateCreditAuthDocJob.perform_later( :user_loan_app_id => self.id )
    end #end only generating if company has setting enabled

  end

  def fields_in_phase(phase)
    json = JSON.parse(UserLoanApp.get_right_structure(self.loan_app_json, phase))
    fields = []
    json["structure"].each do |section|
      fields << section["fields"]
    end
    fields.flatten
  end

  def delete_consent_documents
    loan_doc = self.app_user.user.loan_docs.where( doc_type: "econsent" ).first
    loan_doc.destroy if loan_doc
    loan_doc = self.app_user.user.loan_docs.where( doc_type: "credit_authorization" ).first
    loan_doc.destroy if loan_doc
  end


  def missing_econsent_document?
    if ((self.loan_docs.where(status: ['los-import', 'complete'], doc_type: 'econsent').count == 0 && 
      (self.owner_loan.present? && self.owner_loan.loan_docs.where(status: ['los-import', 'complete'], doc_type: 'econsent').count == 0)) && 
      self.econsent_fields_lookup[:borrower].present? && 
      (self.app_user&.servicer_profile&.company&.generate_econsent_form || self.servicer_profile&.company&.generate_econsent_form))
      return true
    end
    return false
  end

  def econsent_fields_lookup
    return {borrower: nil, coborrower: nil} unless self.app_user

    json = JSON.parse( self.loan_app_json )

    if json["structure"][0].is_a?(Hash)
      structure = [json["structure"]]
    else
      structure = json["structure"]
    end

    borrower_econsent_field = nil
    coborrower_econsent_field = nil

    has_coborrower = json["values"]["has_coborrower"]
    has_coborrower = has_coborrower.present? && value_is_truthy(has_coborrower)

    structure.first(self.phases_complete).each do |phase|
      phase.each do |section|
        if section["fields"].include?( "econsent" )
          borrower_econsent_field = borrower_econsent_field || json["fields"].select{|f| f["key"] == "econsent"}.first
        elsif section["fields"].include?( "econsent_mini" )
          borrower_econsent_field = borrower_econsent_field || json["fields"].select{|f| f["key"] == "econsent_mini"}.first
        end

        if has_coborrower && section["fields"].include?( "coborrower_econsent" )
          coborrower_econsent_field = coborrower_econsent_field || json["fields"].select{|f| f["key"] == "coborrower_econsent"}.first
        end
      end
    end

    return {:borrower => borrower_econsent_field, :coborrower => coborrower_econsent_field}
  end

  # this should be done in a background job as it takes a couple of seconds
  def generate_econsent_document
    @user_loan_app = self # used in the erb
    @user          = self.app_user&.user
    @servicer      = self.app_user&.servicer_profile
    loan_doc       = nil # going to return this

    # for servicer submitted loan apps, the app user will be nil and we swon't have an app_user.servicer_profile. So skip generation.
    if @servicer.present?

      json = JSON.parse( self.loan_app_json )
      econsent_fields = econsent_fields_lookup

      #in multiphase loans, we nil out the submitted_at date. If we need to regenerate this, the date will be nil, so lets temporarily set it to the last log entry so
      # we can regenerate. We won't save it though.
      temporarily_set_submitted_at = false
      if self.submitted_at.nil?
        created_at = user_loan_app_logs.where(event: 'submit').last&.created_at
        self.submitted_at = created_at
        temporarily_set_submitted_at = true
      end

      if self.submitted_at.present? && !econsent_fields.empty? && econsent_fields[:borrower].present?

        @borrower_email = json["values"]["email"].present? ? json["values"]["email"] : @user.email
        @borrower_first_name = json["values"]["first_name"].present? ? json["values"]["first_name"]
          : json["values"]["borrower_first_name"].present? ? json["values"]["borrower_first_name"]
          : @user.name
        @borrower_last_name = json["values"]["last_name"].present? ? json["values"]["last_name"]
          : json["values"]["borrower_last_name"].present? ? json["values"]["borrower_last_name"]
          : @user.last_name

        @coborrower_first_name = json["values"]["coborrower_first_name"]
        @coborrower_last_name = json["values"]["coborrower_last_name"]
        @coborrower_email = json['values']['coborrower_email']

        @econsent_field = econsent_fields[:borrower] 
        @coborrower_econsent_field = econsent_fields[:coborrower]

        @borrower_accepted = false
        if @econsent_field.present?
          @borrower_accepted = self.value_is_truthy(json["values"][@econsent_field["key"]])
        end

        @coborrower_accepted = false
        if @coborrower_econsent_field.present?
          @coborrower_accepted = self.value_is_truthy(json["values"][@coborrower_econsent_field["key"]])
        end


        begin
          econsent_erb  = ERB.new(SystemSetting.econsent_template)
          econsent_html = econsent_erb.result(binding)
          Rails.logger.info "[e-consent] going to html_to_pdf"
          new_pdf      = HtmlToPdf::html_to_pdf(econsent_html).force_encoding('utf-8')
          Rails.logger.info "[e-consent] back from html_to_pdf"
          hash          = Digest::MD5.hexdigest(new_pdf)
          filename      = "E-Consent Document.pdf"

          Rails.logger.info "[e-consent] creating new loandoc"
          loan_doc             = LoanDoc.new
          loan_doc.app_user    = self.app_user
          loan_doc.user        = self.app_user&.user
          if self.owner_loan.present?
            loan_doc.owner     = self.owner_loan
          else
            loan_doc.owner     = self
          end
          loan_doc.name        = filename
          loan_doc.status      = 'los-import'
          loan_doc.doc_type    = 'econsent'
          loan_doc.origin      = 'system'
          loan_doc.fingerprint = hash
          loan_doc.save!
          Rails.logger.info "[e-consent] saved new loan doc: #{loan_doc}"
          

          # since we just saved the doc, force the read from the slave so we can guarantee we have the record
          ActiveRecordSlave.read_from_master do
            loan_doc.reload
          end

          Rails.logger.info "[e-consent] reload new loan doc id: #{loan_doc.id}"

          temp_path            = "#{Rails.root}/tmp/#{loan_doc.guid}-#{filename}"
          File.open(temp_path, 'wb') { |file| file.write( new_pdf ) }
          File.open(temp_path) { |f| loan_doc.image.store!(f) }
          loan_doc.save!
          Rails.logger.info "[e-consent] saved new loan doc to s3: #{loan_doc.image_url}"
          begin
            File.delete(temp_path)
          rescue => ex2 
            NewRelic::Agent.notice_error(ex)
            Rails.logger.error ex
          end


          if @servicer&.effective_loan_los.blank?
            SendEconsentDocToLoJob.perform_later(
              :sp_id => @servicer.id,
              :loan_doc_id => loan_doc.id
            )
          end
        rescue => ex
          NewRelic::Agent.notice_error(ex)
          Rails.logger.error ex.message + "\n" + ex.backtrace.join("\n")
        end
      end
      if temporarily_set_submitted_at
        self.submitted_at = nil
      end
    end

    return loan_doc
  end

  def missing_credit_auth_document?
    if ((self.loan_docs.where(status: ['los-import', 'complete'], doc_type: 'credit_authorization').count == 0 && 
      (self.owner_loan.present? && self.owner_loan.loan_docs.where(status: ['los-import', 'complete'], doc_type: 'credit_authorization').count == 0)) && 
      self.credit_auth_field_lookup[:borrower].present? &&
      (self.app_user&.servicer_profile&.company&.generate_credit_auth_form || self.servicer_profile&.company&.generate_credit_auth_form))
      return true
    end
    return false
  end

  def credit_auth_field_lookup
    @user             = self.app_user&.user
    json              = JSON.parse( self.loan_app_json )
    borrower_credit_auth_field = nil
    if json["structure"][0].is_a?(Hash)
      structure = [json["structure"]]
    else
      structure = json["structure"]
    end
    structure.first(self.phases_complete).each do |phase|
      phase.each do |section|
        if @user.app_user
          if section["fields"].include?( "credit_authorization" )
            borrower_credit_auth_field = json["fields"].select{|f| f["key"] == "credit_authorization"}.first
            break
          end
        end
      end
    end

    coborrower_credit_authorization_field = nil
    if json["structure"][0].is_a?(Hash)
      structure = [json["structure"]]
    else
      structure = json["structure"]
    end
    structure.first(self.phases_complete).each do |phase|
      phase.each do |section|
        if @user.app_user
          if section["fields"].include?( "coborrower_credit_authorization" )
            coborrower_credit_authorization_field =  json["fields"].select{|f| f["key"] == "coborrower_credit_authorization"}.first
          end
        end
      end
    end

    return {:borrower => borrower_credit_auth_field, :coborrower => coborrower_credit_authorization_field}
    
  end


  def generate_credit_auth_document
    @user_loan_app    = self # used in the erb
    @user             = self.app_user&.user
    @servicer         = self.app_user&.servicer_profile
    loan_doc          = nil #returning this

    # for servicer submitted loan apps, the app user will be nil and we swon't have an app_user.servicer_profile. So skip generation.
    if @servicer.present?
      json              = JSON.parse( self.loan_app_json )
      
      credit_auth_fields = credit_auth_field_lookup

      # Use loan app borrower name and email if availible
      @borrower_email = json["values"]["email"].present? ? json["values"]["email"] : @user.email
      @borrower_first_name = json["values"]["first_name"].present? ? json["values"]["first_name"]
        : json["values"]["borrower_first_name"].present? ? json["values"]["borrower_first_name"]
        : @user.name
      @borrower_last_name = json["values"]["last_name"].present? ? json["values"]["last_name"]
        : json["values"]["borrower_last_name"].present? ? json["values"]["borrower_last_name"]
        : @user.last_name

      @coborrower_first_name = json["values"]["coborrower_first_name"]
      @coborrower_last_name = json["values"]["coborrower_last_name"]

      #in multiphase loans, we nil out the submitted_at date. If we need to regenerate this, the date will be nil, so lets temporarily set it to the last log entry so
      # we can regenerate. We won't save it though.
      temporarily_set_submitted_at = false
      if self.submitted_at.nil?
        created_at = user_loan_app_logs.where(event: 'submit').last&.created_at
        self.submitted_at = created_at
        temporarily_set_submitted_at = true
      end

      if self.submitted_at.present? && credit_auth_fields[:borrower].present? && self.value_is_truthy(json["values"][credit_auth_fields[:borrower]["key"]])

        begin
          # used in the html template
          @credit_authorization_field = credit_auth_fields[:borrower] 
          @coborrower_credit_authorization_field = credit_auth_fields[:coborrower]
          @borrower_accepted = self.value_is_truthy(json["values"][credit_auth_fields[:borrower]])
          @coborrower_accepted = self.value_is_truthy(json["values"][credit_auth_fields[:coborrower]])
          credit_auth_erb  = ERB.new(SystemSetting.credit_authorization_template)
          credit_auth_html = credit_auth_erb.result(binding)
          new_pdf      = HtmlToPdf::html_to_pdf(credit_auth_html).force_encoding('utf-8')
          hash          = Digest::MD5.hexdigest(new_pdf)
          filename      = "Credit Authorization Document.pdf"

          loan_doc             = LoanDoc.new
          loan_doc.app_user    = self.app_user
          loan_doc.user        = self.app_user&.user
          if self.owner_loan.present?
            loan_doc.owner     = self.owner_loan
          else
            loan_doc.owner     = self
          end
          loan_doc.name        = filename
          loan_doc.status      = 'los-import'
          loan_doc.doc_type    = 'credit_authorization'
          loan_doc.origin      = 'system'
          loan_doc.fingerprint = hash
          loan_doc.save!

          # since we just saved the doc, force the read from the master so we can guarantee we have the record
          ActiveRecordSlave.read_from_master do
            loan_doc.reload
          end

          temp_path            = "#{Rails.root}/tmp/#{loan_doc.guid}-#{filename}"
          File.open(temp_path, 'wb') { |file| file.write( new_pdf ) }
          File.open(temp_path) { |f| loan_doc.image.store!(f) }
          loan_doc.save!

          begin
            File.delete(temp_path)
          rescue => ex 
            NewRelic::Agent.notice_error(ex)
            Rails.logger.error ex
          end

          if @servicer&.effective_loan_los.blank?
            SendCreditAuthDocToLoJob.perform_later(
              :sp_id => @servicer.id,
              :loan_doc_id => loan_doc.id
            )
          end
        rescue => ex
          NewRelic::Agent.notice_error(ex)
          Rails.logger.error ex.message + "\n" + ex.backtrace.join("\n")
        end   
      end
      if temporarily_set_submitted_at
        self.submitted_at = nil
      end
    end
    
    return loan_doc
  end

  def create_guid
    if guid.blank?
      self.guid = SecureRandom.uuid
    end
  end

  def de_obfuscate
  	self.loan_app_json = de_obfuscate_loan_app_json( self.loan_app_json, self.loan_app_json_was )
  end

  def safe_dictionary_of_values
    dict = {}
    dict['phases_complete'] = self.phases_complete
    return dict
  end

  def has_hmda_multichoice?
    json = JSON.parse( self.loan_app_json)
    json["fields"].each do |field|
      if field["type"] == "multi_choice" && (field["key"] == "ethinicity" or field["key"] == "race" or field["key"] == "coborrower_ethnicity" or field["key"] == "coborrower_race")
        return true
      end
    end
    return false
  end

  def validate_loan_app_json
    json = JSON.parse( self.loan_app_json )
    json["values"].each_key do |key|
      field = json["fields"].select{|f| f["key"] == key}[0]
      if field && field["type"] == "date"
        chronic_date = Chronic.parse( json["values"][key] )
        chronic_date = chronic_date.nil? ? "" : chronic_date.strftime("%m-%d-%Y")
        json["values"][key] = chronic_date
      elsif field && field["type"] == "integer"
        json["values"][key] = json["values"][key].to_f.round.to_s
      elsif field && field["type"] == "currency" && json["values"][key].present?
        json["values"][key] = json["values"][key].to_s.gsub(/[^0-9.]/,'')
      elsif field && field["type"] == "phone" && json["values"][key].present?
        json["values"][key] = json["values"][key].to_s.gsub(/[^0-9]/,'')
      end
    end
    self.loan_app_json = json.to_json
  end

  def clear_cache
    Rails.cache.delete("#{servicer_profile.company.id}_company_loan_apps") if self&.servicer_profile&.company&.present?
    Rails.cache.delete("#{self.app_user.servicer_profile.id}_user_loan_apps") if self.app_user.present? && self.app_user.servicer_profile.present?
    Rails.cache.delete("#{servicer_profile.id}_user_loan_apps") if self.servicer_profile
  end

  def send_created_event
    EventProducer::event("created", {"object" => "UserLoanApp", "id" => self.id})
  end

  def send_to_los_if_submitted
    if self.servicer_profile
      SendToLosJob.perform_later({ lo_id: servicer_profile.id, user_loan_app_id: self.id })
    end
  end

  def all_phases_complete?
    return phases_complete >= total_phases
  end

  def loan_created?
    return phases_complete >= total_phases
  end

end
