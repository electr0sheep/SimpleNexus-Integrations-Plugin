require 'net/http'
require 'open-uri'
require 'json'
require 'benchmark'

class TimePlaceholderReplacement

  n = 100
  s = ServicerProfile.find(1)
  par = s.partners.first
  l = s.loans.first
  i = {
    conditions_1: 'conditions number 1',
    CONDITIONS_2: 'conditions number 2'
  }
  d = {
    'loan_amount': 123123123,
    'PURCHASE_PRICE': '$122,222,222'
  }

  t = %{
    # TEMPLATE PLACEHOLDERS
    [COMPANY_LOGO]
    [COMPANY_LOGO]
    [COMPANY_LOGO_URL]
    [LO_PROFILE_PICTURE]
    [LO_PROFILE_PICTURE_URL]
    [SIGNATURE_IMAGE]
    [SIGNATURE_IMAGE_URL]
    [COMPANY_DIVISION_LABEL]
    [CONDITIONS_1]
    [CONDITIONS_2]
    [LOAN_AMOUNT]
    [PURCHASE_PRICE]
    [STATE_LICENSES_TEXT]

    # NORMAL PLACEHOLDERS
    [ACTIVATION_LINK]
    [INSTALL_LINK]
    [SN_APP_USER_ID]
    [PROPERTY_ADDRESS]
    [APP_USER_NAME]
    [MILESTONES_COMPLETE]
    [MILESTONES_INCOMPLETE]
    [PARTNER_ADDRESS]
    [PARTNER_EMAIL]
    [PARTNER_NAME]
    [PARTNER_PHONE]
    [LOS_LOAN_NUMBER]
    [DOC_NAME]
    [APP_USER_NAME]
    [APP_USER_EMAIL]
    [LO_LINK_TO_APP_USER]
    [APP_USER_PHONE]
    [LOS_USER_NAME]
    [LOS_USER_EMAIL]
    [LOS_USER_CELL]
    [LOS_USER_WORK]
    [LOS_USER_PHONE]
    [CONNECT_LOAN_URL]
    [INVITE_BORROWER_LINK]
    [APP_ICON]
    [APP_NAME]
    [BASE_URL]
    [COMPANY_LOGO]
    [COMPANY_NAME]
    [COMPANY_PHONE]
    [LO_ID]
    [LO_ADDRESS]
    [LO_EMAIL]
    [LO_NAME]
    [LO_TITLE]
    [LO_PHONE]
    [LO_PROFILE_PICTURE]
    [LO_WEBSITE]
    [NMLS_ID]
    [SOCIAL_ICON_LINKS]
    [SUPPORT_EMAIL]
    [DATE]
    [SIGNATURE_IMAGE]
    [SIGNATURE_IMAGE_URL]

    # INJECTED PLACEHOLDERS
    [INSTALL_LINK-IMG-this-is-an-image-src]
    [INSTALL_LINK-TEXT-this-is-an-image-text]

  }.strip

  conn_pars = {
    'loan_number': 123123123,
    'app_user_name': 'app user name',
    'doc_name': 'Doc Name',
    'app_user_email': 'email goes here',
    'app_user_id': 123,
    'app_user_phone': '970-111-1111',
    'los_user_name': 'LOS User',
    'los_user_email_address': 'email@borrower',
    'los_user_cell': '970-222-2222',
    'los_user_phone': '970-333-3333',
    'app_user_device': 'Android',
    'remote_id': 123123123123
  }

  sn_app_user = s.app_users.first

  Benchmark.bm(7) do |x|
    # x.report("old template:") { n.times { s.deprecated_replace_template_placeholders(t.clone, i, d) } }
    x.report("new template:") { n.times { s.replace_template_placeholders(t, i, d) } }
    # x.report("old servicer:") { n.times { s.deprecated_replace_placeholders_in_text(t.clone, nil, l, true, nil, conn_pars, sn_app_user) } }
    x.report("new servicer:") { n.times { s.replace_placeholders_in_text(t, nil, l, true, nil, conn_pars, sn_app_user) } }
    # x.report("old partner:") { n.times { par.deprecated_replace_placeholders_in_text(t.clone, nil, l, true, nil, conn_pars) } }
    x.report("new partner:") { n.times { par.replace_placeholders_in_text(t, nil, l, true, nil, conn_pars, sn_app_user) } }
  end

  # g1 = s.deprecated_replace_template_placeholders(t.clone, i, d)
  g2 = s.replace_template_placeholders(t, i, d)

  # puts 'OLD OLD OLD OLD OLD OLD OLD OLD OLD OLD OLD OLD OLD OLD OLD'
  # puts g1
  puts 'NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW NEW'
  puts g2
end
