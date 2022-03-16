#! /usr/bin/ruby
# Copyright 2002-2008 Rally Software Development Corp. All Rights Reserved. 
require 'rally_ldap_connector'

config_file = ARGV.first

if config_file.nil?
  puts "\n---------------------------------------------------------------" 
  puts "No config file found. Please specify config file when running this script.
  (e.g., 'ldap_rally_service.rb myconfig.xml')\n"
  puts "---------------------------------------------------------------\n\n"
  exit
end

unless FileTest.exist?(config_file)
  puts "\n---------------------------------------------------------------"
  puts "No file by that name ('#{config_file}') found.
  Are you sure you entered an existing file? \n"
  puts "---------------------------------------------------------------\n\n"
  exit
end

puts "\n---------------------------------------------------------------" 
puts "Your use of the Rally Connector for LDAP is governed by the" 
puts "terms and conditions of the applicable Subscription Agreement" 
puts "between your company and Rally Software Development Corp." 
puts "---------------------------------------------------------------\n\n"

@connector = RallyLdapConnector.new(config_file)
@connector.run()