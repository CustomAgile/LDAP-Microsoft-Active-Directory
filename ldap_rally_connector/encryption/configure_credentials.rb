require 'enc_dec'
require 'rexml/document'

# configure_credentials.rb
# script gets 2 inputs from user: 
#  1) Which password are we encrypting?
#  2) What is the password to encrypt?
# Uses enc_dec to encrypt password, creates init. vector (for encryption) and writes this
#  to a file. The init. vector is required for decryption.
# Inserts encrypted password into config.xml and removes unencrypted password

CONFIG_FILE_NAME = '../config.xml'
QUERY_ENTER_PASSWORD = "\n Please enter your password. This will be encrypted and stored in the config.xml file.
  (Note: password cannot be empty) \n : "
SUCCESS_AND_REMINDER = "\n Your password has been encrypted and inserted into the config.xml file.
  Please note that if you need to change your password in the future you will 
  need to run this script again. The plain-text password will not be used to 
  login once an encrypted password has been created. \n \n"

  # search nodes in config.xml for elements containing the text, 'EncryptedPassword'
  # use the results to build the password map and create the query shown to the user
matched_elements = Array.new
pw_map = Hash.new
pw_selection_text = String.new
doc = REXML::Document.new File.new(CONFIG_FILE_NAME)
  # build map based on elements within config.xml that contain the string 'Encrypted'
doc.root.elements.each{ |e| matched_elements.push e if e.name.include? "Encrypted"}
matched_elements.each_with_index { |e, i| pw_map[(i + 1).to_s] = e.name}
  # build string of options to display to user
pw_map.each_pair {|key, value| pw_selection_text << "\t #{key}. #{value.gsub(/Encrypted/, ' ')} \n"}
pw_selection_text << "\n : "

WHICH_PASSWORD_MAP = pw_map
QUERY_WHICH_PASSWORD = "\n This script will replace your current plain-text password with one that is encrypted. \n 
    Which password would you like to encrypt: \n #{pw_selection_text}"

  # get which password we are encrypting from user
  # repeat if they enter invalid option
begin
  print QUERY_WHICH_PASSWORD
  password_element_option = gets.chomp
end until WHICH_PASSWORD_MAP.has_key? password_element_option

password_element_to_encrypt = WHICH_PASSWORD_MAP[password_element_option]

  # get password to encrypt
  # repeat if length <= 0
begin
  print QUERY_ENTER_PASSWORD
  plain_text_password = gets.chomp
end while plain_text_password.empty?

  # encrypt password
encrypted_password = EncDec.encrypt_to_ascii(plain_text_password)

  # update .text with new password
doc.root.elements[password_element_to_encrypt].text = encrypted_password

  # remove non-encrypted password
unless doc.root.elements[password_element_to_encrypt.gsub(/Encrypted/,'')].nil?
  doc.root.elements[password_element_to_encrypt.gsub(/Encrypted/,'')].text = ''
end

  # open config file (actually deletes file and re-creates) and update
config_file = File.open(CONFIG_FILE_NAME, 'w')
config_file.puts(doc)
config_file.close

puts SUCCESS_AND_REMINDER