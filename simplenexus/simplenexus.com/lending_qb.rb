require 'encompass_broker_puller'

class LendingQB < EncompassBrokerPuller

  extend SQS

  def self.fix_num number
    number.present? ? number.to_s.gsub( /[^0-9\.]/,'') : number
  end

  def self.to_date_or_empty(value)
    if value.present?
      date = Chronic.parse(value)
      if date
        return date.strftime('%Y-%m-%d')
      end
    end

    return ""
  end

  def self.to_int_or_empty(value)
    if value.present?
      return value.to_i
    else
      return ''
    end
  end

  def self.value_is_truthy(value)
    self.truthy_values.include? value
  end

  def self.truthy_values
    ["1", 1, "true", "True", "TRUE", true, "Y", "y", "yes", "Yes", "YES"]
  end

  def self.boolean_to_y_n(value)
    if self.value_is_truthy(value)
      return "Y"
    else
      return "N"
    end
  end

  def self.boolean_to_yes_no(value)
    if self.value_is_truthy(value)
      return "Yes"
    else
      return "No"
    end
  end

  def self.get_auth_ticket los = nil
    client = Savon.client do
      wsdl "#{los.url}/los/webservice/AuthService.asmx?wsdl"
      #wsdl "https://secure.lendersoffice.com/los/webservice/AuthService.asmx?wsdl"
    end

    response = client.call(:get_user_auth_ticket) do
      message userName: los.user, passWord: los.pass
      # message userName: "matt@simplenexus.com", passWord: "m5r24h78"
    end

    body = response.body
    ticket = body[:get_user_auth_ticket_response][:get_user_auth_ticket_result]
    ticket
  end

  def self.create_loan los = nil, auth_ticket = nil, user_loan_app_id, lo
    client = Savon.client do
      wsdl "#{los.url}/los/webservice/Loan.asmx?wsdl"
      #wsdl "https://secure.lendersoffice.com/los/webservice/Loan.asmx?wsdl"
    end

    template = User.find(lo.user_id).get_user_setting_value("los_template")

    marital_statuses = { "Married" => "0", "Unmarried" => "1", "Separated" => "2" }

    loan_app = ::UserLoanApp.find(user_loan_app_id)
    json = ActiveSupport::JSON.decode( loan_app.loan_app_json )
    values = json.fetch("values")
    values.each do |key,value|
      values[key] = value.to_s.encode(:xml => :text)
    end
    
    if values["ssn"].present?
      ssn = values["ssn"].gsub( "-", "" )
    else
      ssn = " "
    end
    if values["coborrower_ssn"].present?
      coborrower_ssn = values["coborrower_ssn"].gsub( "-", "" )
    else
      coborrower_ssn = " "
    end

    loan_fields = []

    loan_fields << {:@id => "sStatusLckd", :content! => "True"} 
    loan_fields << {:@id => "sStatusT", :content! => "12"} #new lead? If numeric is needed, it would be "12"
    loan_fields << {:@id => "sLeadD", :content! => Time.now.strftime("%Y-%m-%d")} #new lead? If numeric is needed, it would be "12"

    loan_fields << {:@id => "sEmployeeLoanRepLogin", :@userType => "B", :content! => lo.los_user_id}
    loan_fields << {:@id => "sEmployeeLoanOfficerAssistantLogin", :@userType => "B", :content! => ""}
    loan_fields << {:@id => "sEmployeeProcessorLogin", :@userType => "B", :content! => ""}
    loan_fields << {:@id => "sEmployeeCallCenterAgentLogin", :@userType => "B", :content! => ""}
    loan_fields << {:@id => "sEmployeeManagerLogin", :@userType => "B", :content! => ""}
    loan_fields << {:@id => "sEmployeeUnderwriterLogin", :@userType => "B", :content! => ""}
    loan_fields << {:@id => "sEmployeeLoanOpenerLogin", :@userType => "B", :content! => ""}
    if values['referral_name'].present?
      loan_fields << {:@id => "sEmployeeRealEstateAgentLogin", :@userType => "B", :content! => values['referral_name']}
    else
      loan_fields << {:@id => "sEmployeeRealEstateAgentLogin", :@userType => "B", :content! => ""}
    end
    loan_fields << {:@id => "sEmployeeLenderAccExecLogin", :@userType => "B", :content! => ""}
    loan_fields << {:@id => "sEmployeeLockDeskLogin", :@userType => "B", :content! => ""}

    # loan_fields << {:@id => "sLAmtLckd", :content! => "True"}
    if values['purchase_price'].present?
      loan_fields << {:@id => "sPurchPrice", :content! => fix_num( values['purchase_price'] ).to_f}
    elsif values['loan_amount'].present? && values['down_payment'].present?
      purchase_price = fix_num( values['loan_amount'] ).to_f + fix_num( values['down_payment'] ).to_f
      loan_fields << {:@id => "sPurchPrice", :content! => purchase_price}
    end

    if values['loan_purpose'].present?
      purpose = values['loan_purpose']
      if values['loan_purpose'] == 'Refinance' || values['loan_purpose'] == 'No Cash-Out Refinance'
        values['loan_purpose'] = 1
      elsif values['loan_purpose'] == 'Cash-Out Refinance'
        values['loan_purpose'] = 2
      elsif values['loan_purpose'] == 'Construction'
        values['loan_purpose'] = 3
      else
        values['loan_purpose'] = 0
      end
      loan_fields << {:@id => "sLPurposeT", :content! => values['loan_purpose']}
    else
      purpose = ""
    end

    if template
      template_json = ActiveSupport::JSON.decode(template)
      if template_json
        if template_json[purpose].present? 
          template = template_json[purpose]
        elsif template_json['default'].present?
          template = template_json['default']
        else
          template = ""
        end
      end
    end
    puts "TEMPLATE " + template.to_s

    # CREATE LOAN (based on template selected above)
    option_fields = [
      {:@id => "IsLead", :content! => true},
      {:@id => "TemplateNm", :content! => template},
      {:@id => "IsTestFile", :content! => false}
    ]

    record_fields = [
      {:@id => "Login", :content! => lo.los_user_id},
      {:@id => "UserType", :content! => "B"},
      {:@id => "Role", :content! => "LoanOfficer"}
    ]

    assignment_records = [{field: record_fields}]
    option_collection = [{:@id => "Assignments", :content! => {record: assignment_records}}]

    options = {
      "LOXmlFormat" => {
        :field => option_fields,
        :collection => option_collection
      }
    }
    optionsXml = Gyoku.xml(options)

    response = client.call( :create_with_options ) do
      message sTicket: auth_ticket, optionsXml: optionsXml
    end

    body = response.body
    response_xml = body[:create_with_options_response][:create_with_options_result]
    xml_doc = Nokogiri::XML(response_xml)
    loan_number = xml_doc.xpath("//result//loan//field").text


    puts "created lead: " + loan_number

    if values['loan_amount'].present?
      loan_fields << {:@id => "sLAmtCalc", :content! => fix_num( values['loan_amount'] )}
    end

    if values['down_payment_pct'].present?
      loan_fields << {:@id => "sDownPmtPc", :content! => fix_num( values['down_payment_pct'] ).to_f}
    else
      if values['down_payment'].present?
        # loan_fields << {:@id => "sLAmtLckd", :content! => "false"}
        loan_fields << {:@id => "sEquityCalc", :content! => fix_num( values['down_payment'] )}
      end
    end
    if values['down_payment_explanation'].present?
      if values['down_payment_explanation'].is_a?(Array)
        loan_fields << {:@id => "sDwnPmtSrcExplain", :content! => values['down_payment_explanation'].join(", ")}
      else
        loan_fields << {:@id => "sDwnPmtSrcExplain", :content! => values['down_payment_explanation']}
      end
    end

    if values['property_street'].present?
      loan_fields << {:@id => "sSpAddr", :content! => values['property_street']}
    end
    if values['property_city'].present?
      loan_fields << {:@id => "sSpCity", :content! => values['property_city']}
    end
    if values['property_state'].present?
      loan_fields << {:@id => "sSpState", :content! => values['property_state']}
    end
    if values['property_zip'].present?
      loan_fields << {:@id => "sSpZip", :content! => values['property_zip']}
    end
    if values['property_type'].present?
      if values['property_type'] == 'Single Family Residence'
        values['property_type'] = 0
      elsif values['property_type'] == 'Planned Unit Development'
        values['property_type'] = 1
      elsif values['property_type'] == 'Condo'
        values['property_type'] = 2
      elsif values['property_type'] == 'Cooperative'
        values['property_type'] = 3
      elsif values['property_type'] == 'Manufactured'
        values['property_type'] = 4
      elsif values['property_type'] == 'Two Units'
        values['property_type'] = 8
      elsif values['property_type'] == 'Three Units'
        values['property_type'] = 9
      elsif values['property_type'] == 'Four Units'
        values['property_type'] = 10
      elsif values['property_type'] == 'Modular'
        values['property_type'] = 11
      elsif values['property_type'] == 'Rowhouse'
        values['property_type'] = 12
      end
      loan_fields << {:@id => "sProdSpT", :content! => values['property_type']}
    end
    if values['subject_property_type'].present?
      if values['subject_property_type'] == 'Single Family Residence' || values['subject_property_type'] == 'Detached'
        values['subject_property_type'] = 4
      elsif values['subject_property_type'] == 'Planned Unit Development' || values['subject_property_type'] == 'PUD'
        values['subject_property_type'] = 12
      elsif values['subject_property_type'] == 'Condo' || values['subject_property_type'] == 'Condominium'
        values['subject_property_type'] = 2
      elsif values['subject_property_type'] == 'Manufactured'
        values['subject_property_type'] = 9
      elsif values['subject_property_type'] == 'Modular'
        values['subject_property_type'] = 11
      end
      loan_fields << {:@id => "sGseSpT", :content! => values['subject_property_type']}
    end

    borrower_fields = []
    borrower_fields << {:@id => "aBSsn", :content! => ssn}
    borrower_fields << {:@id => "aBFirstNm", :content! => ( values['first_name'] || '' )}
    borrower_fields << {:@id => "aBMidNm", :content! => ( values['middle_name'] || '' )}
    borrower_fields << {:@id => "aBLastNm", :content! => ( values['last_name'] || '' )}
    if values['suffix'].present?
      borrower_fields << {:@id => "aBSuffix", :content! => values['suffix']}
    end

    if values['dob'].present?
      dob_date = to_date_or_empty(values['dob'])
      borrower_fields << {:@id => "aBDob", :content! => dob_date}
    end

    if values['gender'].present?
      if values['gender'] == "Male"
        values['gender'] = 1
      elsif values['gender'] == "Female"
        values['gender'] = 2
      elsif values['gender'] == "Male and Female"
        values['gender'] = 5
      elsif values['gender'] == "I do not wish to provide this information"
        values['gender'] = 4
      end
      borrower_fields << {:@id => "aBGender", :content! => values['gender']}
    end

    if values['marital_status'].present?
      borrower_fields << {:@id => "aBMaritalStatT", :content! => ( marital_statuses[ values['marital_status'] ] || " " )}
    end

    if values['phone'].present?
      borrower_fields << {:@id => "aBHPhone", :content! => values['phone'].gsub( /\D/, '' )}
    elsif values['borrower_home_phone'].present?
      borrower_fields << {:@id => "aBHPhone", :content! => values['borrower_home_phone'].gsub( /\D/, '' )}
    end
    if values['borrower_cell_phone'].present?
      borrower_fields << {:@id => "aBCellphone", :content! => values['borrower_cell_phone'].gsub( /\D/, '' )}
    elsif values['mobile_phone'].present?
      borrower_fields << {:@id => "aBCellphone", :content! => values['mobile_phone'].gsub( /\D/, '' )}
    elsif values['cell_phone'].present?
      borrower_fields << {:@id => "aBCellphone", :content! => values['cell_phone'].gsub( /\D/, '' )}
    end

    if values['email'].present?
      borrower_fields << {:@id => "aBEmail", :content! => values['email']}
    end

    address = ""
    city = ""
    state = ""
    zip = ""

    if values['address'].present?
      address = values['address']
      borrower_fields << {:@id => "aBAddr", :content! => address}
    end
    if values['city'].present?
      city = values['city']
      borrower_fields << {:@id => "aBCity", :content! => city}
    end
    if values['state'].present?
      state = values['state']
      borrower_fields << {:@id => "aBState", :content! => state}
    end
    if values['zip'].present?
      zip = values['zip']
      borrower_fields << {:@id => "aBZip", :content! => zip}
    end

    if values['mailing_different_than_current'].present? && value_is_truthy(values['mailing_different_than_current'])
      borrower_fields << {:@id => "aBAddrMailSourceT", :content! => 2}
      if values['mailing_address'].present?
        borrower_fields << {:@id => "aBAddrMail", :content! => values['mailing_address']}
      end
      if values['mailing_city'].present?
        borrower_fields << {:@id => "aBCityMail", :content! => values['mailing_city']}
      end
      if values['state'].present?
        borrower_fields << {:@id => "aBStateMail", :content! => values['mailing_state']}
      end
      if values['zip'].present?
        borrower_fields << {:@id => "aBZipMail", :content! => values['mailing_zip']}
      end
    else
      borrower_fields << {:@id => "aBAddrMail", :content! => address}
      borrower_fields << {:@id => "aBCityMail", :content! => city}
      borrower_fields << {:@id => "aBStateMail", :content! => state}
      borrower_fields << {:@id => "aBZipMail", :content! => zip}
    end
    borrower_fields << {:@id => "aBInterviewMethodT", :content! => 4}

    if values['property_own'].present?
      if values['property_own'] == 'Own'
        values['property_own'] = 0
      elsif values['property_own'] == 'Rent'
        values['property_own'] = 1
      elsif values['property_own'] == 'Living Rent Free'
        values['property_own'] = 3
      else
        values['property_own'] = 2
      end
      borrower_fields << {:@id => "aBAddrT", :content! => values['property_own']}
    end
    if values['property_years'].present?
      borrower_fields << {:@id => "aBAddrYrs", :content! => values['property_years']}
    end

    if values['is_firsttimer'].present?
      borrower_fields << {:@id => "aBTotalScoreIsFthb", :content! => value_is_truthy(values['is_firsttimer']) ? "true" : "false"}
    end
    if values['is_veteran'].present?
      borrower_fields << {:@id => "aBIsVeteran", :content! => value_is_truthy(values['is_veteran']) ? "true" : "false"}
    end

    if values['is_self_employed'].present?
      borrower_fields << {:@id => "aBIsSelfEmplmt", :content! => boolean_to_yes_no( values['is_self_employed'] )}
      # employment_fields << {:@id => "IsSelfEmplmt", :content! => boolean_to_yes_no( values['is_self_employed'] )}
    end

    if values['employer_name'].present?
      borrower_fields << {:@id => "aBPrimaryEmplrNm", :content! => ( values['employer_name'] || '' )}
      borrower_fields << {:@id => "aBPrimaryJobTitle", :content! => ( values['job_title'] || '' )}
      borrower_fields << {:@id => "aBPrimaryEmplrAddr", :content! => ( values['employer_address'] || '' )}
      borrower_fields << {:@id => "aBPrimaryEmplrCity", :content! => ( values['employer_city'] || '' )}
      if values['employer_state'].present?
        state = values['employer_state'].split(" - ").last.upcase
        borrower_fields << {:@id => "aBPrimaryEmplrState", :content! => state}
      end

      borrower_fields << {:@id => "aBPrimaryEmplrZip", :content! => ( values["employer_zip"] || '' )}
      if values['employer_years'].present?
        borrower_fields << {:@id => "aBPrimaryEmplmtLen", :content! => to_int_or_empty(values['employer_years'])}
      end
      if values['employer_phone'].present?
        borrower_fields << {:@id => "aBPrimaryEmplrBusPhone", :content! =>  values['employer_phone'] }
      end
      if values['line_of_work'].present?
        borrower_fields << {:@id => "aBPrimaryProfLen", :content! =>  values['line_of_work'] }
      end
      if values['monthly_income'].present?
        borrower_fields << {:@id => "aBBaseI", :content! =>  fix_num( values['monthly_income'] )}
      end
    end

    # previous employers
    borr_employment_records = []
    employment_fields = []
    if values['borrower_previous_employer_name'].present?
      employment_fields << {:@id => "EmplrNm", :content! => values['borrower_previous_employer_name']}
    end
    # employment_fields << {:@id => "JobTitle", :content! => ( values['orrower_previous_job_title'] || '' )}
    # employment_fields << {:@id => "EmplrBusPhone", :content! =>  values['orrower_previous_employer_phone'] }
    if values['borrower_previous_employer_address'].present?
      employment_fields << {:@id => "EmplrAddr", :content! => values['borrower_previous_employer_address']}
    end
    if values['borrower_previous_employer_city'].present?
      employment_fields << {:@id => "EmplrCity", :content! => values['borrower_previous_employer_city']}
    end
    if values['borrower_previous_employer_state'].present?
      state = values['borrower_previous_employer_state'].split(" - ").last.upcase
      employment_fields << {:@id => "EmplrState", :content! => state}
    end
    if values['borrower_previous_employer_zip'].present?
      employment_fields << {:@id => "EmplrZip", :content! => values['borrower_previous_employer_zip']}
    end

    if values['previous_employer_start_date'].present?
      employment_fields << {:@id => "EmplmtStartD", :content! => values['previous_employer_start_date']}
    end
    if values['previous_employer_end_date'].present?
      employment_fields << {:@id => "EmplmtEndD", :content! => values['previous_employer_end_date']}
    end

    if employment_fields.any?
      borr_employment_records << {field: employment_fields}
    end

    if values['has_alimony'].present?
      borrower_fields << {:@id => "aBDecAlimony", :content! => boolean_to_yes_no(values['has_alimony'])}
      if values['alimony_payment'].present?
        borrower_fields << {:@id => "aAlimonyPmt", :content! => fix_num( values['alimony_payment'] )}
      end
    end
    if values['has_bankruptcy'].present?
      borrower_fields << {:@id => "aBDecBankrupt", :content! => boolean_to_yes_no(values['has_bankruptcy'])}
    end
    if values['has_delinquent_debt'].present?
      borrower_fields << {:@id => "aBDecDelinquent", :content! => boolean_to_yes_no(values['has_delinquent_debt'])}
    end
    if values['has_obligations'].present?
      borrower_fields << {:@id => "aBDecObligated", :content! => boolean_to_yes_no(values['has_obligations'])}
    end
    if values['has_outstanding_judgements'].present?
      borrower_fields << {:@id => "aBDecJudgment", :content! => boolean_to_yes_no(values['has_outstanding_judgements'])}
    end
    if values['party_to_lawsuit'].present?
      borrower_fields << {:@id => "aBDecLawsuit", :content! => boolean_to_yes_no(values['party_to_lawsuit'])}
    end
    if values['has_foreclosure'].present?
      borrower_fields << {:@id => "aBDecForeclosure", :content! => boolean_to_yes_no(values['has_foreclosure'])}
    end
    if values['is_comaker_or_endorser'].present?
      borrower_fields << {:@id => "aBDecEndorser", :content! => boolean_to_yes_no(values['is_comaker_or_endorser'])}
    end
    if values['is_primary_residence'].present?
      borrower_fields << {:@id => "aBDecOcc", :content! => boolean_to_yes_no(values['is_primary_residence'])}
    end
    if values['is_down_payment_borrowed'].present?
      borrower_fields << {:@id => "aBDecBorrowing", :content! => boolean_to_yes_no(values['is_down_payment_borrowed'])}
    end
    if values['has_ownership_interest'].present?
      borrower_fields << {:@id => "aBDecPastOwnership", :content! => boolean_to_yes_no(values['has_ownership_interest'])}
    end
    if values['previous_property_type_declaration'].present?
      if values['previous_property_type_declaration'] == 'Primary Residence'
        values['previous_property_type_declaration'] = 1
      elsif values['previous_property_type_declaration'] == 'Second Home'
        values['previous_property_type_declaration'] = 2
      elsif values['previous_property_type_declaration'] == 'Investment Property'
        values['previous_property_type_declaration'] = 3
      end
      borrower_fields << {:@id => "aBDecPastOwnedPropT", :content! => values['previous_property_type_declaration']}
    end
    if values['previous_property_title_declaration'].present?
      if values['previous_property_title_declaration'] == 'Sole Ownership'
        values['previous_property_title_declaration'] = 1
      elsif values['previous_property_title_declaration'] == 'Joint With Spouse'
        values['previous_property_title_declaration'] = 2
      elsif values['previous_property_title_declaration'] == 'Joint With Other Than Spouse'
        values['previous_property_title_declaration'] = 3
      end
      borrower_fields << {:@id => "aBDecPastOwnedPropTitleT", :content! => values['previous_property_title_declaration']}
    end
    if values['occupancy_type'].present?
      if values['occupancy_type'] == 'Primary Residence'
        values['occupancy_type'] = 0
      elsif values['occupancy_type'] == 'Secondary Residence'
        values['occupancy_type'] = 1
      elsif values['occupancy_type'] == 'Investment'
        values['occupancy_type'] = 2
      end
      borrower_fields << {:@id => "aOccT", :content! => values['occupancy_type']}
    elsif values['is_primary_residence'].present?
      borrower_fields << {:@id => "aOccT", :content! => 0}
    end


    if values['number_dependents'].present?
      borrower_fields << {:@id => "aBDependNum", :content! => fix_num( values['number_dependents'] )}
    end
    if values['dependents_age'].present?
      borrower_fields << {:@id => "aBDependAges", :content! => values['dependents_age']}
    end
    if values['school_years'].present?
      borrower_fields << {:@id => "aBSchoolYrs", :content! => to_int_or_empty(values['school_years'])}
    end

    if values['is_us_citizen']
      borrower_fields << {:@id => "aBDecCitizen", :content! => boolean_to_yes_no(values['is_us_citizen'])}
      if values['is_us_citizen'].to_s != "1"
        if values['is_permanent_resident']
          borrower_fields << {:@id => "aBDecResidency", :content! => boolean_to_yes_no(values['is_permanent_resident'])}
        end
      end
    end

    if values['previous_property_type_declaration'].present?
      borrower_fields << {:@id => "aBDecPastOwnedPropT", :content! => values['previous_property_type_declaration']}
    end
    if values['previous_property_title_declaration'].present?
      borrower_fields << {:@id => "aBDecPastOwnedPropTitleT", :content! => values['previous_property_title_declaration']}
    end

    if values['credit_authorization'].to_s == "1"
      borrower_fields << {:@id => "aBCreditAuthorizationD", :content! => loan_app.submitted_at.strftime('%Y-%m-%d')}
    end

    if value_is_truthy(values['provide_demographics'])
      if lo.company&.has_hmda
        borrower_fields.push(*hmda_fields(values,false))
      end 
    end

    asset_records = []
    if values['assets1'].present?
      asset_fields = []
      asset_fields << {:@id => "OwnerT", :content! => 0}
      asset_fields << {:@id => "AssetT", :content! => 3} #checking
      asset_fields << {:@id => "Val", :content! => fix_num( values['assets1'])}
      asset_records << {field: asset_fields}
    end
    if values['assets2'].present?
      asset_fields = []
      asset_fields << {:@id => "OwnerT", :content! => 0}
      asset_fields << {:@id => "AssetT", :content! => 11} #other liquid assets
      asset_fields << {:@id => "Val", :content! => fix_num( values['assets2'])}
      asset_records << {field: asset_fields}
    end
    if values['asset_institution'].present? || values['asset_type'].present?
      asset_fields = []
      asset_fields << {:@id => "OwnerT", :content! => 0}
      asset_fields << {:@id => "ComNm", :content! => ( values['asset_institution'] || '' )}
      if values['asset_type'].present?
        if values['asset_type'] == "Auto"
          values['asset_type'] = 0
        elsif values['asset_type'] == "Bonds"
          values['asset_type'] = 1
        elsif values['asset_type'] == "Checking"
          values['asset_type'] = 3
        elsif values['asset_type'] == "Gift Funds"
          values['asset_type'] = 4
        elsif values['asset_type'] == "Savings"
          values['asset_type'] = 7
        elsif values['asset_type'] == "Stocks"
          values['asset_type'] = 8
        elsif values['asset_type'] == "Other Non-liquid Asset (furniture, jewelry, etc)"
          values['asset_type'] = 9
        elsif values['asset_type'] == "Other Liquid Asset"
          values['asset_type'] = 11
        elsif values['asset_type'] == "Pending Net Sale Proceeds"
          values['asset_type'] = 12
        elsif values['asset_type'] == "Gift Equity"
          values['asset_type'] = 13
        elsif values['asset_type'] == "Certificate of Deposit"
          values['asset_type'] = 14
        elsif values['asset_type'] == "Money Market Fund"
          values['asset_type'] = 15
        elsif values['asset_type'] == "Mutual Funds"
          values['asset_type'] = 16
        elsif values['asset_type'] == "Secured Borrowed Funds"
          values['asset_type'] = 17
        elsif values['asset_type'] == "Bridge Loan Proceeds"
          values['asset_type'] = 18
        elsif values['asset_type'] == "Trust Account"
          values['asset_type'] = 19
        end
        asset_fields << {:@id => "AssetT", :content! => values['asset_type']} #other liquid assets
      end
      asset_records << {field: asset_fields}
    end

    reo_records = []
    reo_fields = []
    if values['real_estate_own_1_address'].present?
      reo_fields << {:@id => "Addr", :content! => values['real_estate_own_1_address']}
    end
    if values['real_estate_own_1_city'].present?
      reo_fields << {:@id => "City", :content! => values['real_estate_own_1_city']}
    end
    if values['real_estate_own_1_state'].present?
      reo_fields << {:@id => "State", :content! => values['real_estate_own_1_state']}
    end
    if values['real_estate_own_1_zip'].present?
      reo_fields << {:@id => "Zip", :content! => values['real_estate_own_1_zip']}
    end
    if reo_fields.any?
      reo_fields.unshift({:@id => "ReOwnerT", :content! => 0})
      reo_records << {field: reo_fields}
    end

    if values['prev_address'].present?
      borrower_fields << {:@id => "aBPrev1Addr", :content! => values['prev_address']}
    end
    if values['prev_city'].present?
      borrower_fields << {:@id => "aBPrev1City", :content! => values['prev_city']}
    end
    if values['prev_state'].present?
      borrower_fields << {:@id => "aBPrev1State", :content! => values['prev_state']}
    end
    if values['prev_zip'].present?
      borrower_fields << {:@id => "aBPrev1Zip", :content! => values['prev_zip']}
    end

    if boolean_to_y_n(values['has_coborrower'])
      borrower_fields << {:@id => "aCSsn", :content! => coborrower_ssn}
      borrower_fields << {:@id => "aCFirstNm", :content! => ( values['coborrower_first_name'] || '' )}
      borrower_fields << {:@id => "aCMidNm", :content! => ( values['coborrower_middle_name'] || '' )}
      borrower_fields << {:@id => "aCLastNm", :content! => ( values['coborrower_last_name'] || '' )}
      if values['coborrower_suffix'].present?
        borrower_fields << {:@id => "aCSuffix", :content! => values['coborrower_suffix']}
      end

      if values['coborrower_dob'].present?
        coborrower_dob_date = to_date_or_empty(values['coborrower_dob'])
        borrower_fields << {:@id => "aCDob", :content! => coborrower_dob_date}
      end

      if values['coborrower_gender'].present?
        if values['coborrower_gender'] == "Male"
          values['coborrower_gender'] = 1
        elsif values['coborrower_gender'] == "Female"
          values['coborrower_gender'] = 2
        elsif values['coborrower_gender'] == "Male and Female"
          values['coborrower_gender'] = 5
        elsif values['coborrower_gender'] == "I do not wish to provide this information"
          values['coborrower_gender'] = 4
        end
        borrower_fields << {:@id => "aCGender", :content! => values['coborrower_gender']}
      end

      if values['coborrower_marital_status'].present?
        borrower_fields << {:@id => "aCMaritalStatT", :content! => ( marital_statuses[ values['coborrower_marital_status'] ] || " " )}
      end

      if values['coborrower_phone'].present?
        borrower_fields << {:@id => "aCHPhone", :content! => values['coborrower_phone'].gsub( /\D/, '' )}
      elsif values['coborrower_home_phone'].present?
        borrower_fields << {:@id => "aCHPhone", :content! => values['coborrower_home_phone'].gsub( /\D/, '' )}
      end
      if values['coborrower_cell_phone'].present?
        borrower_fields << {:@id => "aCCellphone", :content! => values['coborrower_cell_phone'].gsub( /\D/, '' )}
      elsif values['coborrower_mobile_phone'].present?
        borrower_fields << {:@id => "aCCellphone", :content! => values['coborrower_mobile_phone'].gsub( /\D/, '' )}
      elsif values['coborrower_cell_phone'].present?
        borrower_fields << {:@id => "aCCellphone", :content! => values['coborrower_cell_phone'].gsub( /\D/, '' )}
      end

      if values['coborrower_email'].present?
        borrower_fields << {:@id => "aCEmail", :content! => values['coborrower_email']}
      end

      caddress = ""
      ccity = ""
      cstate = ""
      czip = ""

      if values['coborrower_address'].present?
        caddress = values['coborrower_address']
        borrower_fields << {:@id => "aCAddr", :content! => caddress}
      end
      if values['coborrower_city'].present?
        ccity = values['coborrower_city']
        borrower_fields << {:@id => "aCCity", :content! => ccity}
      end
      if values['coborrower_state'].present?
        cstate = values['coborrower_state']
        borrower_fields << {:@id => "aCState", :content! => cstate}
      end
      if values['coborrower_zip'].present?
        czip = values['coborrower_zip']
        borrower_fields << {:@id => "aCZip", :content! => czip}
      end

      if values['coborrower_mailing_different_than_current'].present? && value_is_truthy(values['coborrower_mailing_different_than_current'])
        borrower_fields << {:@id => "aCAddrMailSourceT", :content! => 2}
        if values['coborrower_mailing_address'].present?
          borrower_fields << {:@id => "aCAddrMail", :content! => values['coborrower_mailing_address']}
        end
        if values['coborrower_mailing_city'].present?
          borrower_fields << {:@id => "aCCityMail", :content! => values['coborrower_mailing_city']}
        end
        if values['coborrower_state'].present?
          borrower_fields << {:@id => "aCStateMail", :content! => values['coborrower_mailing_state']}
        end
        if values['coborrower_zip'].present?
          borrower_fields << {:@id => "aCZipMail", :content! => values['coborrower_mailing_zip']}
        end
      else
        borrower_fields << {:@id => "aCAddrMail", :content! => caddress}
        borrower_fields << {:@id => "aCCityMail", :content! => ccity}
        borrower_fields << {:@id => "aCStateMail", :content! => cstate}
        borrower_fields << {:@id => "aCZipMail", :content! => czip}
      end
      borrower_fields << {:@id => "aCInterviewMethodT", :content! => 4}

      if values['coborrower_property_own'].present?
        if values['coborrower_property_own'] == 'Own'
          values['coborrower_property_own'] = 0
        elsif values['coborrower_property_own'] == 'Rent'
          values['coborrower_property_own'] = 1
        elsif values['coborrower_property_own'] == 'Living Rent Free'
          values['coborrower_property_own'] = 3
        else
          values['coborrower_property_own'] = 2
        end
        borrower_fields << {:@id => "aCAddrT", :content! => values['coborrower_property_own']}
      end
      if values['coborrower_property_years'].present?
        borrower_fields << {:@id => "aCAddrYrs", :content! => values['coborrower_property_years']}
      end

      reo_fields = []
      if values['coborrower_real_estate_own_1_address'].present?
        reo_fields << {:@id => "Addr", :content! => values['coborrower_real_estate_own_1_address']}
      end
      if values['coborrower_real_estate_own_1_city'].present?
        reo_fields << {:@id => "City", :content! => values['coborrower_real_estate_own_1_city']}
      end
      if values['coborrower_real_estate_own_1_state'].present?
        reo_fields << {:@id => "State", :content! => values['coborrower_real_estate_own_1_state']}
      end
      if values['coborrower_real_estate_own_1_zip'].present?
        reo_fields << {:@id => "Zip", :content! => values['coborrower_real_estate_own_1_zip']}
      end
      if reo_fields.any?
        reo_fields.unshift({:@id => "ReOwnerT", :content! => 1})
        reo_records << {field: reo_fields}
      end

      if values['coborrower_prev_address'].present?
        borrower_fields << {:@id => "aCPrev1Addr", :content! => values['coborrower_prev_address']}
      end
      if values['coborrower_prev_city'].present?
        borrower_fields << {:@id => "aCPrev1City", :content! => values['coborrower_prev_city']}
      end
      if values['coborrower_prev_state'].present?
        borrower_fields << {:@id => "aCPrev1State", :content! => values['coborrower_prev_state']}
      end
      if values['coborrower_prev_zip'].present?
        borrower_fields << {:@id => "aCPrev1Zip", :content! => values['coborrower_prev_zip']}
      end

      if values['coborrower_is_veteran'].present?
        borrower_fields << {:@id => "aCIsVeteran", :content! => value_is_truthy(values['coborrower_is_veteran']) ? "true" : "false"}
      end

      # employment_fields = []
      if values['coborrower_is_self_employed'].present?
        borrower_fields << {:@id => "aCPrimaryIsSelfEmplmt", :content! => ( value_is_truthy(values['coborrower_is_self_employed']) ? "true" : "false" )}
      end

     if values['coborrower_employer_name'].present?
        borrower_fields << {:@id => "aCPrimaryEmplrNm", :content! => ( values['coborrower_employer_name'] || '' )}
        # employment_fields << {:@id => "EmplrNm", :content! => ( values['coborrower_employer_name'] || '' )}

        borrower_fields << {:@id => "aCPrimaryJobTitle", :content! => ( values['coborrower_job_title'] || '' )}
        # employment_fields << {:@id => "JobTitle", :content! => ( values['coborrower_job_title'] || '' )}

        borrower_fields << {:@id => "aCPrimaryEmplrAddr", :content! => ( values['coborrower_employer_address'] || '' )}
        # employment_fields << {:@id => "EmplrAddr", :content! => ( values['coborrower_employer_address'] || '' )}

        borrower_fields << {:@id => "aCPrimaryEmplrCity", :content! => ( values['coborrower_employer_city'] || '' )}
        # employment_fields << {:@id => "EmplrCity", :content! => ( values['coborrower_employer_city'] || '' )}

        if values['coborrower_employer_state'].present?
          state = values['coborrower_employer_state'].split(" - ").last.upcase
          borrower_fields << {:@id => "aCPrimaryEmplrState", :content! => state}
          # employment_fields << {:@id => "EmplrState", :content! => state}
        end

        borrower_fields << {:@id => "aCPrimaryEmplrZip", :content! => ( values['coborrower_employer_zip'] || '' )}
        # employment_fields << {:@id => "EmplrZip", :content! => ( values['coborrower_employer_zip'] || '' )}

        if values['coborrower_employer_years'].present?
          borrower_fields << {:@id => "aCPrimaryEmplmtLen", :content! => to_int_or_empty(values["coborrower_employer_years"])}
        end
        if values['coborrower_employer_phone'].present?
          borrower_fields << {:@id => "aCPrimaryEmplrBusPhone", :content! =>  values['coborrower_employer_phone'] }
          # employment_fields << {:@id => "EmplrBusPhone", :content! =>  values['coborrower_employer_phone'] }
        end
        if values['coborrower_line_of_work'].present?
          borrower_fields << {:@id => "aCPrimaryProfLen", :content! =>  values['coborrower_line_of_work'] }
        end
        if values['coborrower_monthly_income'].present?
          borrower_fields << {:@id => "aCBaseI", :content! =>  fix_num( values['coborrower_monthly_income'] )}
          # employment_fields << {:@id => "MonI", :content! => fix_num( values['monthly_income'] )}
        end
      end

      cborr_employment_records = []
      employment_fields = []
      if values['coborrower_previous_employer_name'].present?
        employment_fields << {:@id => "EmplrNm", :content! => values['coborrower_previous_employer_name']}
      end
      # employment_fields << {:@id => "JobTitle", :content! => ( values['coborrower_previous_job_title'] || '' )}
      # employment_fields << {:@id => "EmplrBusPhone", :content! =>  values['coborrower_previous_employer_phone'] }
      if values['coborrower_previous_employer_address'].present?
        employment_fields << {:@id => "EmplrAddr", :content! => values['coborrower_previous_employer_address']}
      end
      if values['coborrower_previous_employer_city'].present?
        employment_fields << {:@id => "EmplrCity", :content! => values['coborrower_previous_employer_city']}
      end
      if values['coborrower_previous_employer_state'].present?
        state = values['coborrower_previous_employer_state'].split(" - ").last.upcase
        employment_fields << {:@id => "EmplrState", :content! => state}
      end
      if values['coborrower_previous_employer_zip'].present?
        employment_fields << {:@id => "EmplrZip", :content! => values['coborrower_previous_employer_zip']}
      end

      if values['coborrower_previous_employer_start_date'].present?
        employment_fields << {:@id => "EmplmtStartD", :content! => values['coborrower_previous_employer_start_date']}
      end
      if values['coborrower_previous_employer_end_date'].present?
        employment_fields << {:@id => "EmplmtEndD", :content! => values['coborrower_previous_employer_end_date']}
      end

      if employment_fields.any?
        cborr_employment_records << {field: employment_fields}
      end

      if values['coborrower_has_alimony'].present?
        borrower_fields << {:@id => "aCDecAlimony", :content! => boolean_to_yes_no(values['coborrower_has_alimony'])}
        if values['coborrower_alimony_payment'].present?
          borrower_fields << {:@id => "aAlimonyPmt", :content! => fix_num( values['coborrower_alimony_payment'] )}
        end
      end
      if values['coborrower_has_bankruptcy'].present?
        borrower_fields << {:@id => "aCDecBankrupt", :content! => boolean_to_yes_no(values['coborrower_has_bankruptcy'])}
      end
      if values['coborrower_has_delinquent_debt'].present?
        borrower_fields << {:@id => "aCDecDelinquent", :content! => boolean_to_yes_no(values['coborrower_has_delinquent_debt'])}
      end
      if values['coborrower_has_obligations'].present?
        borrower_fields << {:@id => "aCDecObligated", :content! => boolean_to_yes_no(values['coborrower_has_obligations'])}
      end
      if values['coborrower_has_outstanding_judgements'].present?
        borrower_fields << {:@id => "aCDecJudgment", :content! => boolean_to_yes_no(values['coborrower_has_outstanding_judgements'])}
      end
      if values['coborrower_party_to_lawsuit'].present?
        borrower_fields << {:@id => "aCDecLawsuit", :content! => boolean_to_yes_no(values['coborrower_party_to_lawsuit'])}
      end
      if values['coborrower_has_foreclosure'].present?
        borrower_fields << {:@id => "aCDecForeclosure", :content! => boolean_to_yes_no(values['coborrower_has_foreclosure'])}
      end
      if values['coborrower_is_comaker_or_endorser'].present?
        borrower_fields << {:@id => "aCDecEndorser", :content! => boolean_to_yes_no(values['coborrower_is_comaker_or_endorser'])}
      end
      if values['coborrower_is_primary_residence'].present?
        borrower_fields << {:@id => "aCDecOcc", :content! => boolean_to_yes_no(values['coborrower_is_primary_residence'])}
      end
      if values['coborrower_down_payment_borrowed'].present?
        borrower_fields << {:@id => "aCDecBorrowing", :content! => boolean_to_yes_no(values['coborrower_down_payment_borrowed'])}
      end
      if values['coborrower_has_ownership_interest'].present?
        borrower_fields << {:@id => "aCDecPastOwnership", :content! => boolean_to_yes_no(values['coborrower_has_ownership_interest'])}
      end
      if values['coborrower_previous_property_type_declaration'].present?
        if values['coborrower_previous_property_type_declaration'] == 'Primary Residence'
          values['coborrower_previous_property_type_declaration'] = 1
        elsif values['coborrower_previous_property_type_declaration'] == 'Second Home'
          values['coborrower_previous_property_type_declaration'] = 2
        elsif values['coborrower_previous_property_type_declaration'] == 'Investment Property'
          values['coborrower_previous_property_type_declaration'] = 3
        end
        borrower_fields << {:@id => "aCDecPastOwnedPropT", :content! => values['coborrower_previous_property_type_declaration']}
      end
      if values['coborrower_previous_property_title_declaration'].present?
        if values['coborrower_previous_property_title_declaration'] == 'Sole Ownership'
          values['coborrower_previous_property_title_declaration'] = 1
        elsif values['coborrower_previous_property_title_declaration'] == 'Joint With Spouse'
          values['coborrower_previous_property_title_declaration'] = 2
        elsif values['coborrower_previous_property_title_declaration'] == 'Joint With Other Than Spouse'
          values['coborrower_previous_property_title_declaration'] = 3
        end
        borrower_fields << {:@id => "aCDecPastOwnedPropTitleT", :content! => values['coborrower_previous_property_title_declaration']}
      end

      if values['coborrower_is_us_citizen']
        borrower_fields << {:@id => "aCDecCitizen", :content! => boolean_to_yes_no(values['coborrower_is_us_citizen'])}
        if values['coborrower_is_us_citizen'].to_s != "1"
          if values['coborrower_is_permanent_resident']
            borrower_fields << {:@id => "aCDecResidency", :content! => boolean_to_yes_no(values['coborrower_is_permanent_resident'])}
          end
        end
      end

      if values['coborrower_number_dependents'].present?
        borrower_fields << {:@id => "aCDependNum", :content! => fix_num( values['coborrower_number_dependents'] )}
      end
      if values['coborrower_dependents_age'].present?
        borrower_fields << {:@id => "aCDependAges", :content! => values['coborrower_dependents_age']}
      end
      if values['coborrower_school_years'].present?
        borrower_fields << {:@id => "aCSchoolYrs", :content! => to_int_or_empty(values['coborrower_school_years'])}
      end

      if values['coborrower_previous_property_type_declaration'].present?
        borrower_fields << {:@id => "aCDecPastOwnedPropT", :content! => values['coborrower_previous_property_type_declaration']}
      end
      if values['coborrower_previous_property_title_declaration'].present?
        borrower_fields << {:@id => "aCDecPastOwnedPropTitleT", :content! => values['coborrower_previous_property_title_declaration']}
      end

      if value_is_truthy(values['coborrower_provide_demographics'])
        if lo.company&.has_hmda
          borrower_fields.push(*hmda_fields(values,true))
        end 
      end

      if values['coborrower_credit_authorization'].to_s == "1"
        borrower_fields << {:@id => "aCCreditAuthorizationD", :content! => loan_app.submitted_at.strftime('%Y-%m-%d')}
      end
    end

    collections = []
    if borr_employment_records.any?
      collections << {:@id => "aBEmpCollection", :content! => {record: borr_employment_records}}
    end
    if cborr_employment_records.any?
      collections << {:@id => "aCEmpCollection", :content! => {record: cborr_employment_records}}
    end
    if asset_records.any?
      collections << {:@id => "aAssetCollection", :content! => {record: asset_records}}
    end
    if reo_records.any?
      collections << {:@id => "aReCollection", :content! => {record: reo_records}}
    end

    data = {
      "LOXmlFormat" => {
        "@version" => "1.0",
        :loan => {
          :field => loan_fields,
          :applicant => {
            "@id" => ssn,
            :field => borrower_fields,
            :collection => collections
          }
        }
      }
    }
    data_final = Gyoku.xml(data)
    puts data_final

    response = client.call(:save, message: {
      sTicket: auth_ticket,
      sLNm: loan_number,
      sDataContent: data_final,
      format: 0
    })

    # check response to see if success
    body = response.body
    response = body[:save_response][:save_result]
    puts response
    xml_doc = Nokogiri::XML(response)
    result = xml_doc.xpath("//result").attribute("status").value

    result #OK, OKWithWarning or Error
  end

  def self.hmda_fields(values, is_coborrower)
    sn_prefix = is_coborrower ? "coborrower_" : ""
    lqb_prefix = is_coborrower ? "C" : "B"

    new_fields = []

    if values[sn_prefix+'ethnicity_method'].present?
      method =  (values[sn_prefix+'ethnicity_method'] == "Visual Observation" || values[sn_prefix+'ethnicity_method'] == "Surname") ? 1 : 2
      new_fields << {:@id => "a#{lqb_prefix}EthnicityCollectedByObservationOrSurname", :content! => method}
    end
    if values[sn_prefix+'sex_method'].present?
      method =  (values['sex_method'] == "Visual Observation" || values[sn_prefix+'sex_method'] == "Surname") ? 1 : 2
      new_fields << {:@id => "a#{lqb_prefix}SexCollectedByObservationOrSurname", :content! => method}
    end
    if values[sn_prefix+'race_method'].present?
      method =  (values[sn_prefix+'race_method'] == "Visual Observation" || values[sn_prefix+'race_method'] == "Surname") ? 1 : 2
      new_fields << {:@id => "a#{lqb_prefix}RaceCollectedByObservationOrSurname", :content! => method}
    end

    if values[sn_prefix+'ethnicity'].present?
      if values[sn_prefix+'ethnicity'] == "Hispanic or Latino"
        ethnicity = 1
      elsif values[sn_prefix+'ethnicity'] == "Not Hispanic or Latino"
        ethnicity = 2
      elsif values[sn_prefix+'ethnicity'] == "I do not wish to provide this information"
        ethnicity = nil
      else
        ethnicity = 0
      end
      if ethnicity.present?
        new_fields << {:@id => "a#{lqb_prefix}HispanicT", :content! => ethnicity}
      else
        new_fields << {:@id => "a#{lqb_prefix}DoesNotWishToProvideEthnicity", :content! => "Yes"}
      end
    end

    if values[sn_prefix+'ethnicity_latino'].present?
      if values[sn_prefix+'ethnicity_latino'] == "Mexican"
        new_fields << {:@id => "a#{lqb_prefix}IsMexican", :content! => "Yes"}
      elsif values[sn_prefix+'ethnicity_latino'] == "Puerto Rican"
        new_fields << {:@id => "a#{lqb_prefix}IsPuertoRican", :content! => "Yes"}
      elsif values[sn_prefix+'ethnicity_latino'] == "Cuban"
        new_fields << {:@id => "a#{lqb_prefix}IsCuban", :content! => "Yes"}
      else
        new_fields << {:@id => "a#{lqb_prefix}IsOtherHispanicOrLatino", :content! => "Yes"}
      end
    end

    if values[sn_prefix+'race'].present?
      if values[sn_prefix+'race'] == "American Indian or Alaska Native"
        new_fields << {:@id => "a#{lqb_prefix}IsAmericanIndian", :content! => "Yes"}
      elsif values[sn_prefix+'race'] == "Asian"
        new_fields << {:@id => "a#{lqb_prefix}IsAsian", :content! => "Yes"}
      elsif values[sn_prefix+'race'] == "Black or African American"
        new_fields << {:@id => "a#{lqb_prefix}IsBlack", :content! => "Yes"}
      elsif values[sn_prefix+'race'] == "Native Hawaiian or Other Pacific Islander"
        new_fields << {:@id => "a#{lqb_prefix}IsNativeHawaiian", :content! => "Yes"}
      elsif values[sn_prefix+'race'] == "White"
        new_fields << {:@id => "a#{lqb_prefix}IsWhite", :content! => "Yes"}
      elsif values[sn_prefix+'race'] == "I do not wish to provide this information"
        new_fields << {:@id => "a#{lqb_prefix}DoesNotWishToProvideRace", :content! => "Yes"}
      end
    end

    if values[sn_prefix+'race_asian'].present?
      if values[sn_prefix+'race_asian'] == "Asian Indian"
        new_fields << {:@id => "a#{lqb_prefix}IsAsianIndian", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Chinese"
        new_fields << {:@id => "a#{lqb_prefix}IsChinese", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Filipino"
        new_fields << {:@id => "a#{lqb_prefix}IsFilipino", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Japanese"
        new_fields << {:@id => "a#{lqb_prefix}IsJapanese", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Korean"
        new_fields << {:@id => "a#{lqb_prefix}IsKorean", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Vietnamese"
        new_fields << {:@id => "a#{lqb_prefix}IsVietnamese", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Other Asian"
        new_fields << {:@id => "a#{lqb_prefix}IsOtherAsian", :content! => "Yes"}
      end
    end

    if values[sn_prefix+'pacific_islander'].present?
      if values[sn_prefix+'race_asian'] == "Native Hawaiian"
        new_fields << {:@id => "a#{lqb_prefix}IsNativeHawaiian", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Gamanian or Chamorro"
        new_fields << {:@id => "a#{lqb_prefix}IsGuamanianOrChamorro", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Samoan"
        new_fields << {:@id => "a#{lqb_prefix}IsSamoan", :content! => "Yes"}
      elsif values[sn_prefix+'race_asian'] == "Other Pacific Islaner"
        new_fields << {:@id => "a#{lqb_prefix}IsOtherAsian", :content! => "Yes"}
      end
    end

    if values[sn_prefix+'other_hispanic_or_latino_origin'].present?
      new_fields << {:@id => "a#{lqb_prefix}OtherHispanicOrLatinoDescription", :content! => values[sn_prefix+'other_hispanic_or_latino_origin']}
    end
    if values[sn_prefix+'asian_origin_other'].present?
      new_fields << {:@id => "a#{lqb_prefix}OtherAsianDescription", :content! => values[sn_prefix+'asian_origin_other']}
    end
    if values[sn_prefix+'pacific_islander_other'].present?
      new_fields << {:@id => "a#{lqb_prefix}OtherPacificIslanderDescription", :content! => values[sn_prefix+'pacific_islander_other']}
    end
    if values[sn_prefix+'race_american_indian_other'].present?
      new_fields << {:@id => "a#{lqb_prefix}OtherAmericanIndianDescription", :content! => values[sn_prefix+'race_american_indian_other']}
    end

    new_fields
  end    

  def self.get_modified_loans auth_ticket = nil, los = nil
    loans = []

    loans_xml = nil
    if File.exists?("lqb/lqb_modified_loans.xml") && DEBUG
      puts "reading from lqb/lqb_modified_loans.xml"

      loans_xml = File.read("lqb/lqb_modified_loans.xml")
    else
      client = Savon.client do
        wsdl "#{los.url}/los/webservice/Loan.asmx?wsdl"
      end

      response = client.call(:list_modified_loans_by_app_code) do
        message sTicket: auth_ticket, appCode: los.token #"83e68fb5-0db0-46a0-b82d-a24839750b5a"
      end

      body = response.body
      loans_xml = body[:list_modified_loans_by_app_code_response][:list_modified_loans_by_app_code_result]
      if !File.exists?("lqb")
        Dir.mkdir("lqb")
      end
      File.open("lqb/lqb_modified_loans.xml", "w") { |f| f.write(loans_xml)}

    end
    xml_doc = Nokogiri::XML(loans_xml)
    xml_doc.xpath("//loan").each do |loan_xml|
      loan_map = {}
      #   <loan name="2015110096" old_name="" valid="True" aBNm="Alice Firstimer" aBSsn="991-91-9991" sSpAddr="3726 Poplar St" LastModifiedD="11/24/2015 11:26:59" sStatusT="0" />
      loan_number = loan_xml.attribute("name")
      loan_map["number"] = loan_number.value
      is_valid =  loan_xml.attribute("valid").value == "True" ? true : false
      loan_map["valid"] = is_valid
      # loan_borrower_name = loan_xml.attribute("aBNm")
      # loan_map["borrower_name"] = loan_borrower_name.value
      # loan_borrower_ssn = loan_xml.attribute("aBSsn")
      # loan_map["borrower_ssn"] = loan_borrower_ssn.value
      # loan_address = loan_xml.attribute("sSpAddr")
      # loan_map["address"] = loan_address.value
      # loan_last_modified = loan_xml.attribute("LastModifiedD")
      # loan_map["last_modified"] = loan_last_modified.value

      if !loan_map["number"].start_with?("LEAD") && loan_map["valid"] == true
        loan_map = get_loan(client, auth_ticket, los, loan_map["number"], loan_map)
        if loan_map
          loans << loan_map
        end
      end

    end

    loans

  end

  def self.get_loan client, auth_ticket, los, loan_number, loan_map
    puts "get_loan for #{loan_number}"
    loan_xml = nil
    begin
      if File.exists?("lqb/lqb_#{loan_number}.xml") && DEBUG
        puts "reading from lqb/lqb_#{loan_number}.xml"
        loan_xml = File.read("lqb/lqb_#{loan_number}.xml")
      else
        response = client.call(:load) do
          message sTicket: auth_ticket, sLNm: loan_number, sXmlQuery: LOAN_FIELDS, format:0 #"2015110096"
        end

        body = response.body
        loan_xml = body[:load_response][:load_result]

        if !File.exists?("lqb")
          Dir.mkdir("lqb")
        end
        File.open("lqb/lqb_#{loan_number}.xml", "w") { |f| f.write(loan_xml)}
      end
      #puts loan_xml
      xml_doc = Nokogiri::XML(loan_xml)
      xml_doc.xpath("//loan/field").each do |loan_field|
        #puts loan_field
        loan_map[loan_field.attribute('id').value] = loan_field.content
      end

      applicants = []
      xml_doc.xpath("//loan/applicant").each_with_index do |loan_applicant, index|
        # puts loan_applicant
        applicant_map = {}
        loan_applicant.xpath("field").each do |applicant|
          applicant_map[applicant.attribute('id').value] = applicant.content
        end
        #puts applicant_map
        applicants << applicant_map
      end
      loan_map["borrowers"] = applicants
    rescue => ex
      puts "#{ex}\n#{ex.backtrace}"
      return nil
    end

    loan_map

  end


  def self.remove_loan_from_modified_loans_list auth_ticket, los, loan_number
    #puts "remove_loan_from_modified_loans_list: #{loan_number}"
    if !DEBUG
      client = Savon.client do
        wsdl "#{los.url}/los/webservice/Loan.asmx?wsdl"
      end

      response = client.call(:clear_modified_loan_by_name_by_app_code) do
        message sTicket: auth_ticket, loanName: loan_number, appCode: los.token
      end
    end
    # the response is empty, so we can ignore it
  end

  def self.get_modified_docs auth_ticket, los, timestamp
    client = Savon.client do
      wsdl "#{los.url}/los/webservice/EDocsService.asmx?wsdl"
    end

    modified_date = format_timestamp(timestamp)
    #puts modified_date.to_s
    response = client.call(:list_modified_e_docs_by_app_code) do
      message sTicket: auth_ticket, appCode: los.token, modifiedDate: modified_date
    end

    body = response.body
    docs_xml = body[:list_modified_e_docs_by_app_code_response][:list_modified_e_docs_by_app_code_result]
    #puts docs_xml
    modified_docs = []
    xml_doc = Nokogiri::XML(docs_xml)
    xml_doc.xpath("//eDoc").each do |edoc|
      loan_number = edoc.attribute('LoanNumber').value
      remote_doc_type = edoc.attribute('DocTypeName').value
      modified_doc = {}
      modified_doc[:loan_number] = loan_number
      modified_doc[:remote_doc_type] = remote_doc_type
      # puts "adding #{loan_number} to doc list"
      modified_docs << modified_doc
    end

    modified_docs
  end

  def self.update_loan_docs auth_ticket, los, timestamp
    puts "lending_qb#update_loan_docs"

    modified_docs = get_modified_docs auth_ticket, los, timestamp
    puts "modified docs: #{modified_docs.count}"
    modified_docs.each do |modified_doc|
      loan_number = modified_doc[:loan_number]
      remote_doc_type = modified_doc[:remote_doc_type]
      # do we have this loan.. look it up so we can find a possible loan
      remote_loan = RemoteLoan.where(:loan_los_id => los.id, :loan_number => loan_number).first
      if remote_loan
        #puts "found remote loan: #{remote_loan.id}"
        # see if we've linked up a loan
        loan = remote_loan.loan
        if loan
          #puts "found loan: #{loan.id}"
          # see if we have this loan doc already
          loan_doc = loan.loan_docs.joins(:loan_doc_definition).where('loan_doc_definitions.remote_name = ?', remote_doc_type).first
          if loan_doc
            puts "found loan doc id: #{loan_doc.id}/#{loan_doc.status}"
            if loan_doc.status != 'complete'
              loan_doc.status = 'complete'
            end
            if loan_doc.in_los != 1
              loan_doc.in_los = 1
            end
            loan_doc.save
          end
        end
      end
    end
  end

  #should override the 'base' method in encompass_broker_puller
  def self.update_remote_milestones(remote_loan)
    puts "lendingQB#update_remote_milestones"
    if remote_loan
      ms_response = update_milestones(remote_loan)
      if remote_loan.loan
        update_milestones(remote_loan.loan)
      end
      ms_response
    end
  end

  def self.update_milestones remote_loan
    puts "lendingQB#update_milestones"
    milestone_definition_step = -1
    remote_loan_status = remote_loan.status

    message = nil
    ms_action = "view_milestones"
    ms_name = nil

    # find the matching loan_definition
    ms_loan_definition = nil
    remote_loan.sorted_loan_milestones.each do |loan_milestone|
      # puts remote_loan_status
      # puts loan_milestone.loan_milestone_definition.remote_name
      if remote_loan_status == loan_milestone&.loan_milestone_definition&.remote_name
        milestone_definition_step = loan_milestone.loan_milestone_definition.step
        ms_name = loan_milestone.loan_milestone_definition.name
        break
      end
    end

    # we have found a match
    if milestone_definition_step > -1

      puts "found milestone step #{milestone_definition_step}/#{ms_name} for loan #{remote_loan.id}"
      remote_loan.sorted_loan_milestones.each_with_index do |loan_milestone, index|
        # puts "looking at loan_milestone id: #{loan_milestone.id}, step: #{loan_milestone.loan_milestone_definition.step}, status: #{loan_milestone.status}"
        if loan_milestone.loan_milestone_definition.step == milestone_definition_step && loan_milestone.status != 'complete'
          # puts "marking loan_milestone #{loan_milestone.id} complete"
          loan_milestone.status = 'complete'
          loan_milestone.completed = true
          loan_milestone.status_time = Time.now
          ms_loan_definition = loan_milestone.loan_milestone_definition
          if loan_milestone.message_sent
            ms_loan_definition = nil
          else
            message = loan_milestone.loan_milestone_definition.client_msg
            loan_milestone.message_sent = true
          end
          loan_milestone.save!

          # ensure that the previous milestone was marked completed
          if (index > 0)
            current_milestone_count = index
            while (current_milestone_count != 0) do
              current_milestone_count = current_milestone_count - 1
              previous_milestone = remote_loan.sorted_loan_milestones[current_milestone_count]
              # puts "checking previous_milestone #{previous_milestone.id}/#{previous_milestone.status}"
              if previous_milestone.status != 'complete'
                # puts "marking previous_milestone #{previous_milestone.id} complete"
                previous_milestone.status = 'complete'
                previous_milestone.completed = true
                previous_milestone.message_sent = true
                previous_milestone.status_time = Time.now
                previous_milestone.save!
              end
            end
          end
        end
      end
    end

    if ms_loan_definition
      ms_action = ms_loan_definition.action_type
      if ms_loan_definition.action_details
        ms_name = ms_loan_definition.action_details
      end
    end

    return {"message" => message, "milestone_action" => ms_action, "milestone_name" =>  ms_name, "ms_loan_definition" => ms_loan_definition}
  end


  def self.upload_doc remote_loan = nil, remote_doc_type = "SIMPLENEXUS BORROWER UPLOAD", encoded_file = nil
    Rails.logger.info "LendingQB#upload_lqb_doc"


    client = Savon.client do
      wsdl 'https://secure.lendersoffice.com/los/webservice/AuthService.asmx?wsdl'
    end

    response = client.call(:get_user_auth_ticket) do
      #Hancock credentials
      #message userName: "simplenexus", passWord: "S1mpl3N3xu$"
      message userName: remote_loan.loan_los.user, passWord: remote_loan.loan_los.pass

      # test credentials
      # message userName: "matt@simplenexus.com", passWord: "Password11!"
    end

    body = response.body
    ticket = body[:get_user_auth_ticket_response][:get_user_auth_ticket_result]

    client = Savon.client do
      wsdl "#{remote_loan.loan_los.url}/los/webservice/EDocsService.asmx?wsdl"
    end

#2015110096
#UNASSGINED DOCUMENT TYPE
# BORROWER UPLOAD
    begin
      response = client.call(:upload_pdf_document) do
        message sTicket: ticket, sLNm: remote_loan.loan_number, documentType: remote_doc_type, notes: nil, sDataContent: encoded_file
      end
    rescue => ex
      # puts "#{ex}\n#{ex.backtrace}"
      Rails.logger.error(ex)
      return nil
    end
    body = response.body
    upload_response = body[:upload_pdf_document_response][:upload_pdf_document_result]

    xml_doc = Nokogiri::XML(upload_response)
    status = xml_doc.xpath("//result").attribute("status").value
    if status == "Error"
      NewRelic::Agent.notice_error( "Upload: LendingQB API rejected document of type #{remote_doc_type} for #{remote_loan.loan_number}" )
    end
  end

  def self.convert_lendingqb_xml_to_json(loan)
    response = {}

    response['remote_id'] = loan['number']
    response['loan_id'] = loan['number']
    # response['remote_loan_folder'] = loan['LoanFolder']
    response['remote_last_modified'] = get_date(loan['last_modified'])

    response['loan_officer_email'] = loan['sEmployeeLoanRepEmail']
    # response['lo_nmls'] = loan['lo_nmls']

    response['loan_processor_email'] = loan['sEmployeeProcessorEmail']
    response['remote_loan_created'] = get_date(loan['sLeadD'])
    response['remote_loan_opened'] = get_date(loan['sOpenedD'])
    response['closing_date'] = get_date(loan['sEstCloseD'])
    response['remote_loan_source'] = loan['sLeadSrcDesc']
    response['remote_referral_source'] = loan['sLeadSrcDesc']
    response['remote_rate_locked'] = loan['sRateLockStatusT']
    response['remote_lock_expiration'] = get_date(loan['sRLckdExpiredD'])
    response['econsent_date'] = nil
    response['intent_to_proceed'] = nil
    response['closing_date'] = nil
    response['last_doc_order_date'] = nil
    response['doc_signing_date'] = nil
    response['funding_date'] = nil
    # response['remote_estimated_completion'] = get_time(loan['DateOfEstimatedCompletion'])
    response['loan_program'] = loan['sLpTemplateNm']
    response['loan_type'] = map_loan_type(loan['sLT'])
    response['loan_purpose'] = map_loan_purpose(loan['sLPurposeT'])

    response['loan_term'] = loan['sTerm'].to_i
    response['interest_rate'] = loan['sNoteIR'].nil? ? nil : loan['sNoteIR'].delete("%").to_f
    response['loan_amount'] = to_currency(loan['sLAmtCalc'])
    response['loan_amount_total'] = to_currency(loan['sLAmtCalc'])
    response['downpayment_pct'] = 0
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
    response['payment_frequency'] = 'Monthly'
    response['amortization_type'] = map_amortization_type(loan['sFinMethT'])
    response['cash_from_borrower'] = to_currency(loan['sEquityCalc'])
    response['remote_loan_status'] = loan['sStatusT']
    # response['remote_loan_action_taken'] = loan_info['ActionTaken']
    # response['remote_loan_action_taken_date'] = get_time(loan_info['ActionTakenDate'])

    inactive_loan_statuses = [8,9,10,11]
    if inactive_loan_statuses.include?(loan['sStatusT'].to_i)
      response['remote_loan_active'] = false
    else
      response['remote_loan_active'] = true
    end

    response['borrower'] = {}
    borrower = loan['borrowers'].first
    if borrower
      response['borrower']['first_name'] = borrower['aBFirstNm']
      response['borrower']['last_name'] = borrower['aBLastNm']
      response['borrower']['email_address'] = borrower['aBEmail']
      response['borrower']['phone'] = borrower['aBHPhone']
      response['borrower']['cell_phone'] = borrower['aBCellphone']
      response['borrower']['work_phone'] = borrower['aBBusPhone']
      response['borrower']['ssn'] = borrower['aBSsn']
      response['borrower']['street1'] = borrower['aBAddr']
      response['borrower']['city'] = borrower['aBCity']
      response['borrower']['state'] = borrower['aBState']
      response['borrower']['zip'] = borrower['aBZip']
      response['borrower']['dob'] = borrower['aBDob']

      # we have a coborrower
      if borrower['aCFirstNm'] && !borrower['aCFirstNm'].blank?
        response['co_borrower'] = {}
        response['co_borrower']['first_name'] = borrower['aCFirstNm']
        response['co_borrower']['last_name'] = borrower['aCLastNm']
        response['co_borrower']['email_address'] = borrower['aCEmail']
        response['co_borrower']['phone'] = borrower['aCHPhone']
        response['co_borrower']['cell_phone'] = borrower['aCCellphone']
        response['co_borrower']['work_phone'] = borrower['aCBusPhone']
        response['co_borrower']['ssn'] = borrower['aCSsn']
        response['co_borrower']['street1'] = borrower['aCAddr']
        response['co_borrower']['city'] = borrower['aCCity']
        response['co_borrower']['state'] = borrower['aCState']
        response['co_borrower']['zip'] = borrower['aCZip']
        response['co_borrower']['dob'] = borrower['aCDob']
      end

      #puts borrower['aCreditReportRawXml']
      if borrower['aCreditReportRawXml']
        credit_xml = Nokogiri::XML(borrower['aCreditReportRawXml'])
        if !credit_xml.xpath("//OUTPUT/RESPONSE/ORDER_DETAIL").empty?
          #puts "1-#{credit_xml.xpath("//OUTPUT/RESPONSE/ORDER_DETAIL").attribute('status_code')}"
          puts credit_xml.xpath("//OUTPUT/RESPONSE/ORDER_DETAIL").attribute('report_id')
          response['borrower']['credit_ref_number'] = credit_xml.xpath("//OUTPUT/RESPONSE/ORDER_DETAIL").attribute('report_id')
          #puts credit_xml.xpath("//OUTPUT/RESPONSE/OUTPUT_FORMAT[@format_type='PDF-BASE64']").text
        elsif !credit_xml.xpath("//RESPONSE_GROUP/RESPONSE/RESPONSE_DATA/CREDIT_RESPONSE").empty?
          puts credit_xml.xpath("//RESPONSE_GROUP/RESPONSE/RESPONSE_DATA/CREDIT_RESPONSE").attribute('CreditReportIdentifier')
          response['borrower']['credit_ref_number'] = credit_xml.xpath("//RESPONSE_GROUP/RESPONSE/RESPONSE_DATA/CREDIT_RESPONSE").attribute('CreditReportIdentifier')
        end
      end
    end
    #
    response['property'] = {}
    response['property']['name'] = ''
    response['property']['street'] = loan['sSpAddr']
    response['property']['city'] = loan['sSpCity']
    response['property']['state'] = loan['sSpState']
    response['property']['zip'] = loan['sSpZip']
    response['property']['county'] = loan['sSpCounty']
    response['property']['appraised_value'] = to_currency(loan['sApprVal'])
    # response['property']['estimated_value'] = loan_property['EstimatedValue'].to_f
    response['property']['purchase_price'] = to_currency(loan['sPurchPrice'])

    response
  end

  def self.to_currency(in_value)
    if in_value
      in_value = in_value.delete("$").delete(",")
      in_value.to_f
    else
      in_value
    end
  end

  def self.get_date(unparsed_time)
    Date.strptime(unparsed_time, "%m/%d/%Y").to_s if unparsed_time.present?
  end

  def self.format_timestamp(timestamp)
    timestamp.strftime('%m/%d/%Y %H:%M:%S')
  end

  def self.map_amortization_type(in_amortization_type)
    case in_amortization_type
    when "0"
      "Fixed"
    when "1"
      "ARM"
    when "2"
      "Graduated"
    end
  end

  #    0 - Conventional
  #    1 - FHA
  #    2 - VA
  #    3 - USDA / Rural
  #    4 - Other

  def self.map_loan_type(in_loan_type)
    case in_loan_type
    when "0"
      "Purchase"
    when "1"
      "FHA"
    when "2"
      "VA"
    when "3"
      "USDA / Rural"
    else
      "Other"
    end
  end

  # 0 - Purchase
  # 1 - Refinance
  # 2 - Refinance Cashout
  # 3 - Construct
  # 4 - Construct Permanent
  # 5 - Other
  # 6 - FHA Streamlined Refinance
  # 7 - VA IRRRL

  def self.map_loan_purpose(in_loan_purpose)
    case in_loan_purpose
    when "0"
      "Purchase"
    when "1"
      "Refinance"
    when "2"
      "Refinance Cashout"
    when "3"
      "Construct"
    when "4"
      "Construct Permanent"
    when "5"
      "Other"
    when "6"
      "FHA Streamlnied Refinance"
    when "7"
      "VA IRRRL"
    end
  end



  LOAN_FIELDS = <<-EOF
  <LOXmlFormat version="1.0">
    <field id="Name" />
    <loan>
      <field id="sLPurposeT" />
      <field id="sLT" />
      <field id="sFinMethT" />
      <field id="sRateLockStatusT" />
      <field id="sPurchPrice" />
      <field id="sEquityCalc" />
      <field id="sApprVal" />
      <field id="sLAmtCalc" />
      <field id="sTerm" />
      <field id="sRLckdD" />
      <field id="sRLckdExpiredD" />
      <field id="sNoteIR" />
      <field id="sQualIR" />
      <field id="sLeadD" />
      <field id="sOpenedD" />
      <field id="sEstCloseD" />
      <field id="sLeadSrcDesc" />
      <field id="sLpTemplateNm" />
      <field id="sFinalLAmt" />
      <field id="sEmployeeLoanRepEmail" />
      <field id="sEmployeeProcessorEmail" />
      <field id="sSpAddr" />
      <field id="sSpCity" />
      <field id="sSpState" />
      <field id="sSpZip" />
      <field id="sStatusT" />
      <field id="sLeadSrcDesc" />
      <field id="sTransNetCash" />
      <applicant>
        <field id="aBFirstNm"/>
        <field id="aBLastNm"/>
        <field id="aBSsn"/>
        <field id="aBDob"/>
        <field id="aBHPhone"/>
        <field id="aBCellphone"/>
        <field id="aBBusPhone" />
        <field id="aBAddr"/>
        <field id="aBCity"/>
        <field id="aBState"/>
        <field id="aBZip"/>
        <field id="aBEmail" />
        <field id="aCFirstNm"/>
        <field id="aCLastNm"/>
        <field id="aCSsn"/>
        <field id="aCDob"/>
        <field id="aCCellphone"/>
        <field id="aCHPhone"/>
        <field id="aCBusPhone" />
        <field id="aCAddr"/>
        <field id="aCCity"/>
        <field id="aCState"/>
        <field id="aCZip"/>
        <field id="aCEmail" />
        <field id="aCreditReportRawXml" />
      </applicant>
      <collection id="sCondDataSet"/>
    </loan>
  </LOXmlFormat>
  EOF

#        <collection id="aLiaCollection"/>


end

#view-source:https://secure.lendingqb.com/los/webservice/doc/LOXmlFormatDefinition.xml
#view-source:https://secure.lendingqb.com/los/webservice/doc/LOApplicantIds.xml

# Status
# 0 - Loan Open
# 1 - Loan Prequal
# 2 - Loan Preapproval
# 3 - Loan Submitted
# 4 - Loan Approved
# 5 - Loan Docs
# 6 - Loan Funded
# 7 - Loan On Hold
# 8 - Loan Suspended
# 9 - Loan Canceled
# 10 - Loan Denied
# 11 - Loan Closed
# 12 - Lead new
# 13 - Loan Underwriting
# 15 - Lead Cancel
# 16 - Lead Declined
# 17 - Lead Other
# 18 - Loan Other
# 19 - Loan Recorded
# 21 - Loan Clear To Close
# 22 - Loan Processing
# 23 - Loan FinalUnderwriting
# 24 - Loan DocsBack
# 25 - Loan Funding Conditions
# 26 - Loan Final Docs
# 27 - Loan Sold
# 29 - Loan Pre-Processing
# 30 - Loan Document Check
# 31 - Loan Document Check Failed
# 32 - Loan Pre-Underwriting
# 33 - Loan Condition Review
# 34 - Loan Pre-Doc QC
# 35 - Loan Docs Ordered
# 36 - Loan Docs Drawn
# 37 - Loan Investor Conditions
# 38 - Loan Investor Conditions Sent
# 39 - Loan Ready For Sale
# 40 - Loan Submitted For Purchase Review
# 41 - Loan In Purchase Review
# 42 - Loan Pre-Purchase Conditions
# 43 - Loan Submitted For Final Purchase Review
# 44 - Loan In Final Purchase Review
# 45 - Loan Clear To Purchase
# 46 - Loan Purchased
# 47 - Loan Counter Offer
# 48 - Loan Withdrawn
# 49 - Loan Archived
