require 'openssl'
require 'digest/sha1'

# enc_dec.rb
# static methods only
# Provides Encryption / Decryption using 256 bit AES-CBC

# NOTE: EncDec::decrypt will raise an exception when passed an invalid string
#  Use rescue clause around any calls to EncDec::decrpyt

class EncDec

  @@YOUR_KEY = "yourEncryptionKey"
  @@ENCRYPTION_TYPE = "aes-256-cbc"
  @@IV_SEED = "245 116 4 58 148 85 65 174 141 207 17 64 70 23 127 65"
    
  def EncDec.encrypt(plain_text)
    cipher = OpenSSL::Cipher::Cipher.new(@@ENCRYPTION_TYPE)
    cipher.encrypt
    
    # used to encrypt / decrypt
    cipher.key = key = Digest::SHA1.hexdigest(@@YOUR_KEY)
    cipher.iv = @@IV_SEED
    
    encrypted_text = cipher.update(plain_text)
    encrypted_text << cipher.final
    
    return encrypted_text
  end
  
  def EncDec.decrypt(encrypted_text)
    
    cipher = OpenSSL::Cipher::Cipher.new(@@ENCRYPTION_TYPE)
    cipher.decrypt

    cipher.key = key = Digest::SHA1.hexdigest(@@YOUR_KEY)
    cipher.iv = @@IV_SEED
    begin
      decrypted_text = cipher.update(encrypted_text)
      decrypted_text << cipher.final
    rescue
      raise
    end
    return decrypted_text
  end
  
  def EncDec.encrypt_to_ascii(plain_text)
    self.string_to_ascii(self.encrypt(plain_text))
  end
  
    # To be called when the encrypted text has been converted to space-delimited ascii
  def EncDec.decrypt_from_ascii(encrypted_ascii)
    self.decrypt(ascii_to_string(encrypted_ascii))
  end
  
  def EncDec.string_to_ascii(string)
    ascii_array = Array.new
    string.each_byte { |b| ascii_array.push b}
    ascii_array.join(' ')
  end
  
  def EncDec.ascii_to_string(ascii)
    temp_array = Array.new
    ascii.strip.split(" ").each {|b| temp_array << b.to_i.chr}
    temp_array.join
  end
  
end