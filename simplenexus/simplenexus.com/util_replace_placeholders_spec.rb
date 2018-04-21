require "rails_helper"
require './lib/util'

RSpec.describe "Util replace placeholders" do
  before :all do
    @servicer_profile = ::FactoryGirl.create(:servicer_profile_with_contacts)
    @partner          = @servicer_profile.partners[0]
    @app_user         = @servicer_profile.app_users[0]
    @user             = @servicer_profile.user
  end

  def replace_for_servicer text
    Util.replace_placeholders_in_text(text: text, servicer: @servicer_profile)
  end

  def replace_for_partner text
    Util.replace_placeholders_in_text(text: text, partner: @partner)
  end

  def replace_for_app_user text
    Util.replace_placeholders_in_text(text: text, app_user: @app_user)
  end

  def replace_for_user text
    Util.replace_placeholders_in_text(text: text, user: @user)
  end

  describe "for servicer" do


    context "with placeholder" do
      it "[ACTIVATION_LINK]" do
        text = "[ACTIVATION_LINK]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.default_installation_link )
      end
      it "[ADDRESS]" do
        text = "[ADDRESS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.formatted_address )
      end
      it "[APP_ICON]" do
        text = "[APP_ICON]"
        key = "<img src='#{@servicer_profile.effective_app_icon_url}' alt='app icon' width='100' />"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( key )
      end
      it "[APP_NAME]" do
        text = "[APP_NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.effective_app_name )
      end
      it "[APP_USER_EMAIL]" do
        text = "[APP_USER_EMAIL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[APP_USER_ID]" do
        text = "[APP_USER_ID]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[APP_USER_NAME]" do
        text = "[APP_USER_NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[APP_USER_PHONE]" do
        text = "[APP_USER_PHONE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[AUTHENTICATION_TOKEN]" do
        text = "[AUTHENTICATION_TOKEN]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.user.authentication_token || '' )
      end
      it "[BASE_URL]" do
        text = "[BASE_URL]"
        replaced = replace_for_servicer( text )
        key = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        expect( replaced ).to eq( key )
      end
      it "[BORROWER_SIGNUP_URL]" do
        text = "[BORROWER_SIGNUP_URL]"
        replaced = replace_for_servicer( text )
        base_url = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        key = base_url + '/borrower/signup/' + @servicer_profile.email
        expect( replaced ).to eq( key )
      end
      it "[BRANCH_ADDRESS]" do
        text = "[BRANCH_ADDRESS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.effective_branch_address )
      end
      it "[COMPANY_ADDRESS]" do
        text = "[COMPANY_ADDRESS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_address )
      end
      it "[COMPANY_LOGO]" do
        text = "[COMPANY_LOGO]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( "<img src='#{@servicer_profile.effective_company_logo_url}' alt='company logo' width='565' style='width: 565px;border: none;font-size: 14px;font-weight: bold;outline: none;text-decoration: none;text-transform: capitalize;vertical-align:middle;padding:6px;' />" )
      end
      it "[COMPANY_NAME]" do
        text = "[COMPANY_NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_name )
      end
      it "[COMPANY_PHONE]" do
        text = "[COMPANY_PHONE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_phone )
      end
      it "[CONNECT_LOAN_URL-IMG-URL]" do
        text = "[CONNECT_LOAN_URL-IMG-URL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[CONNECT_LOAN_URL]" do
        text = "[CONNECT_LOAN_URL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[DATE]" do
        text = "[DATE]"
        key = Time.now.strftime("%B %e, %Y")
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( key )
      end
      it "[DOC_NAME]" do
        text = "[DOC_NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[EMAIL]" do
        text = "[EMAIL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.email )
      end
      it "[INSTALL_LINK-IMG-URL]" do
        text = "[INSTALL_LINK-IMG-URL]"
        replaced = replace_for_servicer( text )
        text.gsub!(/\[INSTALL_LINK-IMG-(.*?)\]/) { "<a href='#{ @servicer_profile.default_installation_link }'><img src='#{$1}' alt='link image' /></a>" }
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK-TEXT-TEXT]" do
        text = "[INSTALL_LINK-TEXT-TEXT]"
        replaced = replace_for_servicer( text )
        text.gsub!(/\[INSTALL_LINK-TEXT-(.*?)\]/) { "<a href='#{ @servicer_profile.default_installation_link }'>#{$1}</a>" }
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK]" do
        text = "[INSTALL_LINK]"
        key = "<a href='#{ @servicer_profile.default_installation_link }'>#{ @servicer_profile.default_installation_link }</a>"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( key )
      end
      it "[INVITE_BORROWER_LINK]" do
        text = "[INVITE_BORROWER_LINK]"
        replaced = replace_for_servicer( text )
        base_url = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        invite_borrower_link = "#{ base_url }/install/send_borrower_invitation_to_install_app/#{ @servicer_profile.id }?input[remote_id]="
        key = "<a href='#{ invite_borrower_link }'>Click here to share the app with the borrower</a>."
        expect( replaced ).to eq( key )
      end
      it "[LO_ADDRESS]" do
        text = "[LO_ADDRESS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.formatted_address )
      end
      it "[LO_CITY]" do
        text = "[LO_CITY]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.city )
      end
      it "[LO_COMPANY_LICENSE-CA]" do
        text = "[LO_COMPANY_LICENSE-CA]"
        replaced = replace_for_servicer( text )
        text.gsub!(/\[LO_COMPANY_LICENSE-(.*?)\]/) do
          state = "#{$1}"
          @servicer_profile.company.license_by_state( state )
        end
        expect( replaced ).to eq( text )
      end
      it "[LO_COMPANY_NMLS_ID]" do
        text = "[LO_COMPANY_NMLS_ID]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile&.company&.nmls || '' )
      end
      it "[LO_EMAIL]" do
        text = "[LO_EMAIL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.email )
      end
      it "[LO_ID]" do
        text = "[LO_ID]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.id.to_s )
      end
      it "[LO_LICENSE-CA]" do
        text = "[LO_LICENSE-CA]"
        replaced = replace_for_servicer( text )
        text.gsub!(/\[LO_LICENSE-(.*?)\]/) do
          state = "#{$1}"
          @servicer_profile.license_by_state( state )
        end
        expect( replaced ).to eq( text )
      end
      it "[LO_LINK_TO_APP_USER]" do
        text = "[LO_LINK_TO_APP_USER]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[LO_NAME]" do
        text = "[LO_NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.full_name )
      end
      it "[LO_OFFICE_PHONE]" do
        text = "[LO_OFFICE_PHONE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.office_phone || "" )
      end
      it "[LO_PHONE]" do
        text = "[LO_PHONE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.phone || "" )
      end
      it "[LO_PROFILE_PICTURE]" do
        text = "[LO_PROFILE_PICTURE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( "<img src='#{@servicer_profile.profile.url}' alt='LO profile picture' />" )
      end
      it "[LO_STATE]" do
        text = "[LO_STATE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.state )
      end
      it "[LO_STREET]" do
        text = "[LO_STREET]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.formatted_street_address )
      end
      it "[LO_TITLE]" do
        text = "[LO_TITLE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.title || "")
      end
      it "[LO_WEBSITE]" do
        text = "[LO_WEBSITE]"
        replaced = replace_for_servicer( text )
        key = "<a href='#{ @servicer_profile.effective_website }'>#{ @servicer_profile.effective_website }</a>"
        expect( replaced ).to eq( key )
      end
      it "[LO_ZIP]" do
        text = "[LO_ZIP]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.zip )
      end
      it "[LOAN_APP_AGREEMENT_FIELDS]" do
        text = "[LOAN_APP_AGREEMENT_FIELDS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( "[LOAN_APP_AGREEMENT_FIELDS]" )
      end
      it "[LOS_LOAN_NUMBER]" do
        text = "[LOS_LOAN_NUMBER]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_CELL]" do
        text = "[LOS_USER_CELL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_EMAIL]" do
        text = "[LOS_USER_EMAIL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_NAME]" do
        text = "[LOS_USER_NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_PHONE]" do
        text = "[LOS_USER_PHONE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_WORK]" do
        text = "[LOS_USER_WORK]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[MILESTONES_COMPLETE]" do
        text = "[MILESTONES_COMPLETE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[MILESTONES_INCOMPLETE]" do
        text = "[MILESTONES_INCOMPLETE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[NAME]" do
        text = "[NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.full_name )
      end
      it "[NMLS_ID]" do
        text = "[NMLS_ID]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.license )
      end
      it "[PARTNER_ADDRESS]" do
        text = "[PARTNER_ADDRESS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_CITY]" do
        text = "[PARTNER_CITY]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_EMAIL]" do
        text = "[PARTNER_EMAIL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_FIRST_NAME]" do
        text = "[PARTNER_FIRST_NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_NAME]" do
        text = "[PARTNER_NAME]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_PHONE]" do
        text = "[PARTNER_PHONE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_PROFILE_PICTURE]" do
        text = "[PARTNER_PROFILE_PICTURE]"
        replaced = replace_for_servicer( text )
        key = "<img src='' alt='partner profile picture' />"
        expect( replaced ).to eq( key )
      end
      it "[PARTNER_STATE]" do
        text = "[PARTNER_STATE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_STREET]" do
        text = "[PARTNER_STREET]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_ZIP]" do
        text = "[PARTNER_ZIP]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[PHONE]" do
        text = "[PHONE]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.phone )
      end
      it "[PROPERTY_ADDRESS]" do
        text = "[PROPERTY_ADDRESS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[REGION_ADDRESS]" do
        text = "[REGION_ADDRESS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.effective_region_address )
      end
      it "[SIGNATURE_IMAGE]" do
        text = "[SIGNATURE_IMAGE]"
        replaced = replace_for_servicer( text )
        key = @servicer_profile.user.signature_url.present? ? "<img src='#{@servicer_profile.user.signature_url}' alt='Signature image' />" : ""
        expect( replaced ).to eq( key )
      end
      it "[SIGNATURE_IMAGE_URL]" do
        text = "[SIGNATURE_IMAGE_URL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( '' )
      end
      it "[SN_APP_USER_ID]" do
        text = "[SN_APP_USER_ID]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.user.signature_url || "" )
      end
      it "[SN_CITY_STATE_ZIP]" do
        text = "[SN_CITY_STATE_ZIP]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( "Lehi, UT 84043" )
      end
      it "[SN_STREET_ADDRESS]" do
        text = "[SN_STREET_ADDRESS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( "2600 Executive Parkway, Suite 300" )
      end
      it "[SOCIAL_ICON_LINKS]" do
        text = "[SOCIAL_ICON_LINKS]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.social_links.collect{|l| "<a href='#{l.url}'>Link</a>"}.join('') )
      end
      it "[SUPPORT_EMAIL]" do
        text = "[SUPPORT_EMAIL]"
        replaced = replace_for_servicer( text )
        expect( replaced ).to eq( @servicer_profile.effective_support_email )
      end
    end
  end # END SERVICER

  describe "for partner" do

    context "with placeholder" do
      it "[ACTIVATION_LINK]" do
        text = "[ACTIVATION_LINK]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @partner.servicer_activation_code.short_url )
      end
      it "[ADDRESS]" do
        text = "[ADDRESS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.formatted_address )
      end
      it "[APP_ICON]" do
        text = "[APP_ICON]"
        key = "<img src='#{@servicer_profile.effective_app_icon_url}' alt='app icon' width='100' />"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( key )
      end
      it "[APP_NAME]" do
        text = "[APP_NAME]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.effective_app_name )
      end
      it "[APP_USER_EMAIL]" do
        text = "[APP_USER_EMAIL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[APP_USER_ID]" do
        text = "[APP_USER_ID]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[APP_USER_NAME]" do
        text = "[APP_USER_NAME]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[APP_USER_PHONE]" do
        text = "[APP_USER_PHONE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[AUTHENTICATION_TOKEN]" do
        text = "[AUTHENTICATION_TOKEN]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.user.authentication_token || '' )
      end
      it "[BASE_URL]" do
        text = "[BASE_URL]"
        replaced = replace_for_partner( text )
        key = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        expect( replaced ).to eq( key )
      end
      it "[BORROWER_SIGNUP_URL]" do
        text = "[BORROWER_SIGNUP_URL]"
        replaced = replace_for_partner( text )
        base_url = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        key = base_url + '/borrower/signup/' + @partner.email
        expect( replaced ).to eq( key )
      end
      it "[BRANCH_ADDRESS]" do
        text = "[BRANCH_ADDRESS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.effective_branch_address )
      end
      it "[COMPANY_ADDRESS]" do
        text = "[COMPANY_ADDRESS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_address )
      end
      it "[COMPANY_LOGO]" do
        text = "[COMPANY_LOGO]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( "<img src='#{@servicer_profile.effective_company_logo_url}' alt='company logo' width='565' style='width: 565px;border: none;font-size: 14px;font-weight: bold;outline: none;text-decoration: none;text-transform: capitalize;vertical-align:middle;padding:6px;' />" )
      end
      it "[COMPANY_NAME]" do
        text = "[COMPANY_NAME]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_name )
      end
      it "[COMPANY_PHONE]" do
        text = "[COMPANY_PHONE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_phone )
      end
      it "[CONNECT_LOAN_URL-IMG-URL]" do
        text = "[CONNECT_LOAN_URL-IMG-URL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[CONNECT_LOAN_URL]" do
        text = "[CONNECT_LOAN_URL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[DATE]" do
        text = "[DATE]"
        key = Time.now.strftime("%B %e, %Y")
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( key )
      end
      it "[DOC_NAME]" do
        text = "[DOC_NAME]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[EMAIL]" do
        text = "[EMAIL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @partner.email )
      end
      it "[INSTALL_LINK-IMG-URL]" do
        text = "[INSTALL_LINK-IMG-URL]"
        replaced = replace_for_partner( text )
        text.gsub!(/\[INSTALL_LINK-IMG-(.*?)\]/) { "<a href='#{ @partner.servicer_activation_code.short_url }'><img src='#{$1}' alt='link image' /></a>" }
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK-TEXT-TEXT]" do
        text = "[INSTALL_LINK-TEXT-TEXT]"
        replaced = replace_for_partner( text )
        text.gsub!(/\[INSTALL_LINK-TEXT-(.*?)\]/) { "<a href='#{ @partner.servicer_activation_code.short_url }'>#{$1}</a>" }
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK]" do
        text = "[INSTALL_LINK]"
        key = "<a href='#{ @partner.servicer_activation_code.short_url }'>#{ @partner.servicer_activation_code.short_url }</a>"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( key )
      end
      it "[INVITE_BORROWER_LINK]" do
        text = "[INVITE_BORROWER_LINK]"
        replaced = replace_for_partner( text )
        base_url = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        install_link = @partner.servicer_activation_code.short_url
        key = "<a href='#{ base_url}/install/send_generic_styled_email?input[email]=&input[subject]=Track Your Mortgage With #{@partner.name}&input[access_code]=#{@partner.email}&id=#{@partner.id}&input[message]=Hi ,<br><br>Track Your loan progress, and send documentation in from your mobile device.  <br><br>You can download the app here: #{ install_link }'>Click here to share the app with .</a>"
        expect( replaced ).to eq( key )
      end
      it "[LO_ADDRESS]" do
        text = "[LO_ADDRESS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.formatted_address )
      end
      it "[LO_CITY]" do
        text = "[LO_CITY]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.city )
      end
      it "[LO_COMPANY_LICENSE-CA]" do
        text = "[LO_COMPANY_LICENSE-CA]"
        replaced = replace_for_partner( text )
        text.gsub!(/\[LO_COMPANY_LICENSE-(.*?)\]/) do
          state = "#{$1}"
          @servicer_profile.company.license_by_state( state )
        end
        expect( replaced ).to eq( text )
      end
      it "[LO_COMPANY_NMLS_ID]" do
        text = "[LO_COMPANY_NMLS_ID]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile&.company&.nmls || '' )
      end
      it "[LO_EMAIL]" do
        text = "[LO_EMAIL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.email )
      end
      it "[LO_ID]" do
        text = "[LO_ID]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.id.to_s )
      end
      it "[LO_LICENSE-CA]" do
        text = "[LO_LICENSE-CA]"
        replaced = replace_for_partner( text )
        text.gsub!(/\[LO_LICENSE-(.*?)\]/) do
          state = "#{$1}"
          @servicer_profile.license_by_state( state )
        end
        expect( replaced ).to eq( text )
      end
      it "[LO_LINK_TO_APP_USER]" do
        text = "[LO_LINK_TO_APP_USER]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[LO_NAME]" do
        text = "[LO_NAME]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.full_name )
      end
      it "[LO_OFFICE_PHONE]" do
        text = "[LO_OFFICE_PHONE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.office_phone || "" )
      end
      it "[LO_PHONE]" do
        text = "[LO_PHONE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.phone || "" )
      end
      it "[LO_PROFILE_PICTURE]" do
        text = "[LO_PROFILE_PICTURE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( "<img src='#{@servicer_profile.profile.url}' alt='LO profile picture' />" )
      end
      it "[LO_STATE]" do
        text = "[LO_STATE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.state )
      end
      it "[LO_STREET]" do
        text = "[LO_STREET]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.formatted_street_address )
      end
      it "[LO_TITLE]" do
        text = "[LO_TITLE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.title || "")
      end
      it "[LO_WEBSITE]" do
        text = "[LO_WEBSITE]"
        replaced = replace_for_partner( text )
        key = "<a href='#{ @servicer_profile.effective_website }'>#{ @servicer_profile.effective_website }</a>"
        expect( replaced ).to eq( key )
      end
      it "[LO_ZIP]" do
        text = "[LO_ZIP]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.zip )
      end
      it "[LOAN_APP_AGREEMENT_FIELDS]" do
        text = "[LOAN_APP_AGREEMENT_FIELDS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( "[LOAN_APP_AGREEMENT_FIELDS]" )
      end
      it "[LOS_LOAN_NUMBER]" do
        text = "[LOS_LOAN_NUMBER]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_CELL]" do
        text = "[LOS_USER_CELL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_EMAIL]" do
        text = "[LOS_USER_EMAIL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_NAME]" do
        text = "[LOS_USER_NAME]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_PHONE]" do
        text = "[LOS_USER_PHONE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_WORK]" do
        text = "[LOS_USER_WORK]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[MILESTONES_COMPLETE]" do
        text = "[MILESTONES_COMPLETE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[MILESTONES_INCOMPLETE]" do
        text = "[MILESTONES_INCOMPLETE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[NAME]" do
        text = "[NAME]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @partner.full_name )
      end
      it "[NMLS_ID]" do
        text = "[NMLS_ID]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.license )
      end
      it "[PARTNER_ADDRESS]" do
        text = "[PARTNER_ADDRESS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_CITY]" do
        text = "[PARTNER_CITY]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_EMAIL]" do
        text = "[PARTNER_EMAIL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @partner.email )
      end
      it "[PARTNER_FIRST_NAME]" do
        text = "[PARTNER_FIRST_NAME]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @partner.name )
      end
      it "[PARTNER_NAME]" do
        text = "[PARTNER_NAME]"
        replaced = replace_for_partner( text )
        key = "#{@partner.try(:name)} #{@partner.try(:last_name)}"
        expect( replaced ).to eq( key )
      end
      it "[PARTNER_PHONE]" do
        text = "[PARTNER_PHONE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @partner.phone )
      end
      it "[PARTNER_PROFILE_PICTURE]" do
        text = "[PARTNER_PROFILE_PICTURE]"
        replaced = replace_for_partner( text )
        key = "<img src='#{@partner.try(:profile).try(:url)}' alt='partner profile picture' />"
        expect( replaced ).to eq( key )
      end
      it "[PARTNER_STATE]" do
        text = "[PARTNER_STATE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_STREET]" do
        text = "[PARTNER_STREET]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_ZIP]" do
        text = "[PARTNER_ZIP]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[PHONE]" do
        text = "[PHONE]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @partner.phone )
      end
      it "[PROPERTY_ADDRESS]" do
        text = "[PROPERTY_ADDRESS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[REGION_ADDRESS]" do
        text = "[REGION_ADDRESS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.effective_region_address )
      end
      it "[SIGNATURE_IMAGE]" do
        text = "[SIGNATURE_IMAGE]"
        replaced = replace_for_partner( text )
        key = @servicer_profile.user.signature_url.present? ? "<img src='#{@servicer_profile.user.signature_url}' alt='Signature image' />" : ""
        expect( replaced ).to eq( key )
      end
      it "[SIGNATURE_IMAGE_URL]" do
        text = "[SIGNATURE_IMAGE_URL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( '' )
      end
      it "[SN_APP_USER_ID]" do
        text = "[SN_APP_USER_ID]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.user.signature_url || "" )
      end
      it "[SN_CITY_STATE_ZIP]" do
        text = "[SN_CITY_STATE_ZIP]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( "Lehi, UT 84043" )
      end
      it "[SN_STREET_ADDRESS]" do
        text = "[SN_STREET_ADDRESS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( "2600 Executive Parkway, Suite 300" )
      end
      it "[SOCIAL_ICON_LINKS]" do
        text = "[SOCIAL_ICON_LINKS]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.social_links.collect{|l| "<a href='#{l.url}'>Link</a>"}.join('') )
      end
      it "[SUPPORT_EMAIL]" do
        text = "[SUPPORT_EMAIL]"
        replaced = replace_for_partner( text )
        expect( replaced ).to eq( @servicer_profile.effective_support_email )
      end
    end
  end # END PARTNER

  describe "for app user" do

    context "with placeholder" do
      it "[ACTIVATION_LINK]" do
        text = "[ACTIVATION_LINK]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @app_user.servicer_activation_code.short_url )
      end
      it "[ADDRESS]" do
        text = "[ADDRESS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.formatted_address )
      end
      it "[APP_ICON]" do
        text = "[APP_ICON]"
        key = "<img src='#{@servicer_profile.effective_app_icon_url}' alt='app icon' width='100' />"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( key )
      end
      it "[APP_NAME]" do
        text = "[APP_NAME]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.effective_app_name )
      end
      it "[APP_USER_EMAIL]" do
        text = "[APP_USER_EMAIL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @app_user.email )
      end
      it "[APP_USER_ID]" do
        text = "[APP_USER_ID]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @app_user.id.to_s )
      end
      it "[APP_USER_NAME]" do
        text = "[APP_USER_NAME]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @app_user.name )
      end
      it "[APP_USER_PHONE]" do
        text = "[APP_USER_PHONE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @app_user.phone )
      end
      it "[AUTHENTICATION_TOKEN]" do
        text = "[AUTHENTICATION_TOKEN]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.user.authentication_token || '' )
      end
      it "[BASE_URL]" do
        text = "[BASE_URL]"
        replaced = replace_for_app_user( text )
        key = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        expect( replaced ).to eq( key )
      end
      it "[BORROWER_SIGNUP_URL]" do
        text = "[BORROWER_SIGNUP_URL]"
        replaced = replace_for_app_user( text )
        base_url = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        key = base_url + '/borrower/signup/' + @servicer_profile.email
        expect( replaced ).to eq( key )
      end
      it "[BRANCH_ADDRESS]" do
        text = "[BRANCH_ADDRESS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.effective_branch_address )
      end
      it "[COMPANY_ADDRESS]" do
        text = "[COMPANY_ADDRESS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_address )
      end
      it "[COMPANY_LOGO]" do
        text = "[COMPANY_LOGO]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( "<img src='#{@servicer_profile.effective_company_logo_url}' alt='company logo' width='565' style='width: 565px;border: none;font-size: 14px;font-weight: bold;outline: none;text-decoration: none;text-transform: capitalize;vertical-align:middle;padding:6px;' />" )
      end
      it "[COMPANY_NAME]" do
        text = "[COMPANY_NAME]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_name )
      end
      it "[COMPANY_PHONE]" do
        text = "[COMPANY_PHONE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.effective_company_phone )
      end
      it "[CONNECT_LOAN_URL-IMG-URL]" do
        text = "[CONNECT_LOAN_URL-IMG-URL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[CONNECT_LOAN_URL]" do
        text = "[CONNECT_LOAN_URL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[DATE]" do
        text = "[DATE]"
        key = Time.now.strftime("%B %e, %Y")
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( key )
      end
      it "[DOC_NAME]" do
        text = "[DOC_NAME]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[EMAIL]" do
        text = "[EMAIL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @app_user.servicer_profile.email )
      end
      it "[INSTALL_LINK-IMG-URL]" do
        text = "[INSTALL_LINK-IMG-URL]"
        replaced = replace_for_app_user( text )
        text.gsub!(/\[INSTALL_LINK-IMG-(.*?)\]/) { "<a href='#{ @app_user.servicer_activation_code.short_url }'><img src='#{$1}' alt='link image' /></a>" }
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK-TEXT-TEXT]" do
        text = "[INSTALL_LINK-TEXT-TEXT]"
        replaced = replace_for_app_user( text )
        text.gsub!(/\[INSTALL_LINK-TEXT-(.*?)\]/) { "<a href='#{ @app_user.servicer_activation_code.short_url }'>#{$1}</a>" }
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK]" do
        text = "[INSTALL_LINK]"
        key = "<a href='#{ @app_user.servicer_activation_code.short_url }'>#{ @app_user.servicer_activation_code.short_url }</a>"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( key )
      end
      it "[INVITE_BORROWER_LINK]" do
        text = "[INVITE_BORROWER_LINK]"
        replaced = replace_for_app_user( text )
        base_url = @servicer_profile&.user&.company&.installation_base_url&.present? ? @servicer_profile.user.company.installation_base_url : 'https://simplenexus.com'
        invite_borrower_link = "#{ base_url }/install/send_borrower_invitation_to_install_app/#{ @servicer_profile.id }?input[remote_id]="
        key = "<a href='#{ invite_borrower_link }'>Click here to share the app with the borrower</a>."
        expect( replaced ).to eq( key )
      end
      it "[LO_ADDRESS]" do
        text = "[LO_ADDRESS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.formatted_address )
      end
      it "[LO_CITY]" do
        text = "[LO_CITY]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.city )
      end
      it "[LO_COMPANY_LICENSE-CA]" do
        text = "[LO_COMPANY_LICENSE-CA]"
        replaced = replace_for_app_user( text )
        text.gsub!(/\[LO_COMPANY_LICENSE-(.*?)\]/) do
          state = "#{$1}"
          @servicer_profile.company.license_by_state( state )
        end
        expect( replaced ).to eq( text )
      end
      it "[LO_COMPANY_NMLS_ID]" do
        text = "[LO_COMPANY_NMLS_ID]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile&.company&.nmls || '' )
      end
      it "[LO_EMAIL]" do
        text = "[LO_EMAIL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.email )
      end
      it "[LO_ID]" do
        text = "[LO_ID]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.id.to_s )
      end
      it "[LO_LICENSE-CA]" do
        text = "[LO_LICENSE-CA]"
        replaced = replace_for_app_user( text )
        text.gsub!(/\[LO_LICENSE-(.*?)\]/) do
          state = "#{$1}"
          @servicer_profile.license_by_state( state )
        end
        expect( replaced ).to eq( text )
      end
      it "[LO_LINK_TO_APP_USER]" do
        text = "[LO_LINK_TO_APP_USER]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( "<a href='https://simplenexus.com/servicer_leads/index/#{@servicer_profile.id}?search_code=#{@app_user.id}'>https://simplenexus.com/servicer_leads/index/#{@servicer_profile.id}?search_code=#{@app_user.id}</a>" )
      end
      it "[LO_NAME]" do
        text = "[LO_NAME]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.full_name )
      end
      it "[LO_OFFICE_PHONE]" do
        text = "[LO_OFFICE_PHONE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.office_phone || "" )
      end
      it "[LO_PHONE]" do
        text = "[LO_PHONE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.phone || "" )
      end
      it "[LO_PROFILE_PICTURE]" do
        text = "[LO_PROFILE_PICTURE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( "<img src='#{@servicer_profile.profile.url}' alt='LO profile picture' />" )
      end
      it "[LO_STATE]" do
        text = "[LO_STATE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.state )
      end
      it "[LO_STREET]" do
        text = "[LO_STREET]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.formatted_street_address )
      end
      it "[LO_TITLE]" do
        text = "[LO_TITLE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.title || "")
      end
      it "[LO_WEBSITE]" do
        text = "[LO_WEBSITE]"
        replaced = replace_for_app_user( text )
        key = "<a href='#{ @servicer_profile.effective_website }'>#{ @servicer_profile.effective_website }</a>"
        expect( replaced ).to eq( key )
      end
      it "[LO_ZIP]" do
        text = "[LO_ZIP]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.zip )
      end
      it "[LOAN_APP_AGREEMENT_FIELDS]" do
        text = "[LOAN_APP_AGREEMENT_FIELDS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( "No agreement fields to report." )
      end
      it "[LOS_LOAN_NUMBER]" do
        text = "[LOS_LOAN_NUMBER]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_CELL]" do
        text = "[LOS_USER_CELL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_EMAIL]" do
        text = "[LOS_USER_EMAIL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_NAME]" do
        text = "[LOS_USER_NAME]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_PHONE]" do
        text = "[LOS_USER_PHONE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[LOS_USER_WORK]" do
        text = "[LOS_USER_WORK]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[MILESTONES_COMPLETE]" do
        text = "[MILESTONES_COMPLETE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[MILESTONES_INCOMPLETE]" do
        text = "[MILESTONES_INCOMPLETE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[NAME]" do
        text = "[NAME]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @app_user.servicer_profile.full_name )
      end
      it "[NMLS_ID]" do
        text = "[NMLS_ID]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.license )
      end
      it "[PARTNER_ADDRESS]" do
        text = "[PARTNER_ADDRESS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_CITY]" do
        text = "[PARTNER_CITY]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_EMAIL]" do
        text = "[PARTNER_EMAIL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @user&.partner&.email || "" )
      end
      it "[PARTNER_FIRST_NAME]" do
        text = "[PARTNER_FIRST_NAME]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @user&.partner&.name || "" )
      end
      it "[PARTNER_NAME]" do
        text = "[PARTNER_NAME]"
        replaced = replace_for_app_user( text )
        key = @user.partner ? "#{@user&.partner&.name} #{@user&.partner&.last_name}" : ""
        expect( replaced ).to eq( key )
      end
      it "[PARTNER_PHONE]" do
        text = "[PARTNER_PHONE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @user&.partner&.phone || "" )
      end
      it "[PARTNER_PROFILE_PICTURE]" do
        text = "[PARTNER_PROFILE_PICTURE]"
        replaced = replace_for_app_user( text )
        key = "<img src='#{@user.partner.try(:profile).try(:url)}' alt='partner profile picture' />"
        expect( replaced ).to eq( key )
      end
      it "[PARTNER_STATE]" do
        text = "[PARTNER_STATE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_STREET]" do
        text = "[PARTNER_STREET]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[PARTNER_ZIP]" do
        text = "[PARTNER_ZIP]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[PHONE]" do
        text = "[PHONE]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( (@user.partner || @servicer_profile).phone )
      end
      it "[PROPERTY_ADDRESS]" do
        text = "[PROPERTY_ADDRESS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[REGION_ADDRESS]" do
        text = "[REGION_ADDRESS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.effective_region_address )
      end
      it "[SIGNATURE_IMAGE]" do
        text = "[SIGNATURE_IMAGE]"
        replaced = replace_for_app_user( text )
        key = @servicer_profile.user.signature_url.present? ? "<img src='#{@servicer_profile.user.signature_url}' alt='Signature image' />" : ""
        expect( replaced ).to eq( key )
      end
      it "[SIGNATURE_IMAGE_URL]" do
        text = "[SIGNATURE_IMAGE_URL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( '' )
      end
      it "[SN_APP_USER_ID]" do
        text = "[SN_APP_USER_ID]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @app_user.id.to_s )
      end
      it "[SN_CITY_STATE_ZIP]" do
        text = "[SN_CITY_STATE_ZIP]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( "Lehi, UT 84043" )
      end
      it "[SN_STREET_ADDRESS]" do
        text = "[SN_STREET_ADDRESS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( "2600 Executive Parkway, Suite 300" )
      end
      it "[SOCIAL_ICON_LINKS]" do
        text = "[SOCIAL_ICON_LINKS]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.social_links.collect{|l| "<a href='#{l.url}'>Link</a>"}.join('') )
      end
      it "[SUPPORT_EMAIL]" do
        text = "[SUPPORT_EMAIL]"
        replaced = replace_for_app_user( text )
        expect( replaced ).to eq( @servicer_profile.effective_support_email )
      end
    end
  end # END APP_USER

  describe "for user" do

    context "with placeholder" do
      it "[ACTIVATION_LINK]" do
        text = "[ACTIVATION_LINK]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[ADDRESS]" do
        text = "[ADDRESS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[APP_ICON]" do
        text = "[APP_ICON]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[APP_NAME]" do
        text = "[APP_NAME]"
        replaced = replace_for_user( text )
        key = @user.company.effective_app_name.present? ? @user.company.effective_app_name : text
        expect( replaced ).to eq( key )
      end
      it "[APP_USER_EMAIL]" do
        text = "[APP_USER_EMAIL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[APP_USER_ID]" do
        text = "[APP_USER_ID]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[APP_USER_NAME]" do
        text = "[APP_USER_NAME]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[APP_USER_PHONE]" do
        text = "[APP_USER_PHONE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[AUTHENTICATION_TOKEN]" do
        text = "[AUTHENTICATION_TOKEN]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[BASE_URL]" do
        text = "[BASE_URL]"
        replaced = replace_for_user( text )
        key = "https://simplenexus.com"
        expect( replaced ).to eq( key )
      end
      it "[BRANCH_ADDRESS]" do
        text = "[BRANCH_ADDRESS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[COMPANY_ADDRESS]" do
        text = "[COMPANY_ADDRESS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[COMPANY_LOGO]" do
        text = "[COMPANY_LOGO]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[COMPANY_NAME]" do
        text = "[COMPANY_NAME]"
        replaced = replace_for_user( text )
        key = @user.company.effective_company_name.present? ? @user.company.effective_company_name : text
        expect( replaced ).to eq( key )
      end
      it "[COMPANY_PHONE]" do
        text = "[COMPANY_PHONE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[CONNECT_LOAN_URL-IMG-URL]" do
        text = "[CONNECT_LOAN_URL-IMG-URL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[CONNECT_LOAN_URL]" do
        text = "[CONNECT_LOAN_URL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[DATE]" do
        text = "[DATE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[DOC_NAME]" do
        text = "[DOC_NAME]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[EMAIL]" do
        text = "[EMAIL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK-IMG-URL]" do
        text = "[INSTALL_LINK-IMG-URL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK-TEXT-TEXT]" do
        text = "[INSTALL_LINK-TEXT-TEXT]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[INSTALL_LINK]" do
        text = "[INSTALL_LINK]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[INVITE_BORROWER_LINK]" do
        text = "[INVITE_BORROWER_LINK]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_ADDRESS]" do
        text = "[LO_ADDRESS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_CITY]" do
        text = "[LO_CITY]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_COMPANY_LICENSE-CA]" do
        text = "[LO_COMPANY_LICENSE-CA]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_COMPANY_NMLS_ID]" do
        text = "[LO_COMPANY_NMLS_ID]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_EMAIL]" do
        text = "[LO_EMAIL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_ID]" do
        text = "[LO_ID]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_LICENSE-CA]" do
        text = "[LO_LICENSE-CA]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_LINK_TO_APP_USER]" do
        text = "[LO_LINK_TO_APP_USER]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_NAME]" do
        text = "[LO_NAME]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_OFFICE_PHONE]" do
        text = "[LO_OFFICE_PHONE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_PHONE]" do
        text = "[LO_PHONE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_PROFILE_PICTURE]" do
        text = "[LO_PROFILE_PICTURE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_STATE]" do
        text = "[LO_STATE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_STREET]" do
        text = "[LO_STREET]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_TITLE]" do
        text = "[LO_TITLE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_WEBSITE]" do
        text = "[LO_WEBSITE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LO_ZIP]" do
        text = "[LO_ZIP]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LOAN_APP_AGREEMENT_FIELDS]" do
        text = "[LOAN_APP_AGREEMENT_FIELDS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LOS_LOAN_NUMBER]" do
        text = "[LOS_LOAN_NUMBER]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LOS_USER_CELL]" do
        text = "[LOS_USER_CELL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LOS_USER_EMAIL]" do
        text = "[LOS_USER_EMAIL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LOS_USER_NAME]" do
        text = "[LOS_USER_NAME]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LOS_USER_PHONE]" do
        text = "[LOS_USER_PHONE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[LOS_USER_WORK]" do
        text = "[LOS_USER_WORK]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[MAIN_SOLID_THEME_COLOR]" do
        text = "[MAIN_SOLID_THEME_COLOR]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( "#F0F0F0" )
      end
      it "[MAIN_SOLID_THEME_FONT_COLOR]" do
        text = "[MAIN_SOLID_THEME_FONT_COLOR]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( "#00FF00" )
      end
      it "[MILESTONES_COMPLETE]" do
        text = "[MILESTONES_COMPLETE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[MILESTONES_INCOMPLETE]" do
        text = "[MILESTONES_INCOMPLETE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[NAME]" do
        text = "[NAME]"
        replaced = replace_for_user( text )
        key = @user.full_name.present? ? @user.full_name : text
        expect( replaced ).to eq( key )
      end
      it "[NMLS_ID]" do
        text = "[NMLS_ID]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_ADDRESS]" do
        text = "[PARTNER_ADDRESS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_CITY]" do
        text = "[PARTNER_CITY]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_EMAIL]" do
        text = "[PARTNER_EMAIL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_FIRST_NAME]" do
        text = "[PARTNER_FIRST_NAME]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_NAME]" do
        text = "[PARTNER_NAME]"
        replaced = replace_for_user( text )
        key = @user.partner ? "#{@user&.partner&.name} #{@user&.partner&.last_name}" : ""
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_PHONE]" do
        text = "[PARTNER_PHONE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_PROFILE_PICTURE]" do
        text = "[PARTNER_PROFILE_PICTURE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_STATE]" do
        text = "[PARTNER_STATE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_STREET]" do
        text = "[PARTNER_STREET]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PARTNER_ZIP]" do
        text = "[PARTNER_ZIP]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PHONE]" do
        text = "[PHONE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[PROPERTY_ADDRESS]" do
        text = "[PROPERTY_ADDRESS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[REGION_ADDRESS]" do
        text = "[REGION_ADDRESS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[SIGNATURE_IMAGE]" do
        text = "[SIGNATURE_IMAGE]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[SIGNATURE_IMAGE_URL]" do
        text = "[SIGNATURE_IMAGE_URL]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[SN_APP_USER_ID]" do
        text = "[SN_APP_USER_ID]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[SN_CITY_STATE_ZIP]" do
        text = "[SN_CITY_STATE_ZIP]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[SN_STREET_ADDRESS]" do
        text = "[SN_STREET_ADDRESS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[SOCIAL_ICON_LINKS]" do
        text = "[SOCIAL_ICON_LINKS]"
        replaced = replace_for_user( text )
        expect( replaced ).to eq( text )
      end
      it "[SUPPORT_EMAIL]" do
        text = "[SUPPORT_EMAIL]"
        replaced = replace_for_user( text )
        key = @user.company.support_email.present? ? @user.company.support_email : text
        expect( replaced ).to eq( key )
      end
    end
  end # END USER
end
