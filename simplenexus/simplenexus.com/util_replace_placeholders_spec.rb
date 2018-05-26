require "rails_helper"
require './lib/util'
require 'pry'

RSpec.describe "Util replace placeholders" do
  before :all do
    @servicer_profile = ::FactoryGirl.create(:servicer_profile_with_contacts)
    @partner          = @servicer_profile.partners[0]
    @app_user         = @servicer_profile.app_users[0]
    @values = Hash.new( nil  )
    @values['remote_id'] = '1234567'
    @values['loan_number'] = '1234567'
    @values['app_user_name'] = @app_user.name
    @values['app_user_email'] = @app_user.email
    @values['app_user_phone'] = @app_user.phone
    @values['app_user_device'] = @app_user.device_id
    @values['los_loan_number'] = "12345"
    @values['doc_name'] = "Driver_License.pdf"
    @values['los_user_name'] = @app_user.name
    @values['los_user_email'] = @app_user.email
    @values['los_user_cell'] = @app_user.phone
    @values['los_user_work'] = @app_user.phone
    @values['los_user_phone'] = @app_user.phone
    @values['remote_id'] = "1234"
  end

  def replace_for_servicer text
    Util.replace_placeholders_in_text(text, nil, @servicer_profile, @values)
  end

  def replace_for_partner text
    Util.replace_placeholders_in_text(text, nil, @partner, @values)
  end

  def replace_for_app_user text
    Util.replace_placeholders_in_text(text, @app_user, nil, @values)
  end

  describe "Placeholder replacement" do
    it "Activation Code" do
      text = "{{ activation_code.value }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(@servicer_profile.default_code.code)
      expect(p_text).to eq(@partner.servicer_activation_code.code)
      expect(au_text).to eq(@app_user.servicer_activation_code.code)
    end

    it "Intall URL" do
      text = "{{ values.install_url }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(@servicer_profile.default_code.short_url)
      expect(p_text).to eq(@partner.servicer_activation_code.short_url)
      expect(au_text).to eq(@app_user.servicer_activation_code.short_url)
    end

    it "Doc Name" do
      text = "{{ values.doc_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      expect(p_text).to eq(au_text)
      expect(au_text).to eq(@values['doc_name']) 
    end

    it "LO App User Link" do
      text = "{{ values.lo_link_to_app_user }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      expect(au_text).to eq("#{@servicer_profile.safe_dictionary_of_values['base_url']}/servicer_leads/index/#{@servicer_profile&.id}?search_code=#{@app_user&.user&.email}")
    end

    it "Los_loan_Number" do
      text = "{{ values.los_loan_number }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      expect(p_text).to eq(au_text)
      expect(au_text).to eq(@values['los_loan_number'])
    end

    it "LOS User Name" do
      text = "{{ values.los_user_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      expect(p_text).to eq(au_text)
      expect(au_text).to eq(@values['los_user_name']) 
    end

    it "LOS User email" do
      text = "{{ values.los_user_email }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      expect(p_text).to eq(au_text)
      expect(au_text).to eq(@values['los_user_email'])
    end

    it "LOS user cell" do
      text = "{{ values.los_user_cell }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      expect(p_text).to eq(au_text)
      expect(au_text).to eq(@values['los_user_cell'])
    end

    it "LOS User Work" do
      text = "{{ values.los_user_work }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      expect(p_text).to eq(au_text)
      expect(au_text).to eq(@values['los_user_work'])
    end

    it "LOS User Phone" do
      text = "{{ values.los_user_phone }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      expect(p_text).to eq(au_text)
      expect(au_text).to eq(@values['los_user_phone'])
    end

    it "Enrollment URL" do
      text = "{{ values.enrollment_url }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
    end

    it "Placeholder here" do
      text = "{{ servicer.app_icon }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.app_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ app_user.email }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ app_user.full_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ app_user.first_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ app_user.phone }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.base_url }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.first_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.full_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.first_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.borrower_base_url }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.borrower_signup_url }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.company_logo }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.address }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.email }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.support_email }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.profile_picture }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.nmls_id }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.signature_image }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.signature_image_url }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ servicer.social_links }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ partner.social_links }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ partner.borrower_signup_url }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      
    end

    it "Placeholder here" do
      text = "{{ partner.address }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ partner.email }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(p_text).to eq (@partner.email)
    end

    it "Placeholder here" do
      text = "{{ partner.first_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(p_text).to eq (@partner.name)
    end

    it "Placeholder here" do
      text = "{{ partner.full_name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(p_text).to eq(@partner.full_name)
      
    end

    it "Placeholder here" do
      text = "{{ partner.profile_picture }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
    end

    it "Placeholder here" do
      text = "{{ company.name }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ user_loan_app.agreement_fields }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
    end

    it "Placeholder here" do
      text = "{{ user_loan_app.total_phases }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ loan.completed_milestones }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ loan.incomplete_milestones }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

    it "Placeholder here" do
      text = "{{ loan.property_address }}"
      s_text = replace_for_servicer text
      p_text = replace_for_partner text
      au_text = replace_for_app_user text
      expect(s_text).to eq(p_text)
      
    end

  end
end
