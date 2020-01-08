# Copyright (C) 2019 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'securerandom'
require 'digest'

module Mongo
  module Crypt

    # A helper module that implements cryptography methods required
    # for native Ruby crypto hooks. These methods are passed into FFI
    # as C callbacks and called from the libmongocrypt library.
    #
    # @api private
    module Hooks

      # An AES encrypt or decrypt method.
      #
      # @param [ FFI::Pointer ] key_binary_p A pointer to a mongocrypt_binary_t
      #   object that wraps the 32-byte AES encryption key
      # @param [ FFI::Pointer ] iv_binary_p A pointer to a mongocrypt_binary_t
      #   object that wraps the 16-byte AES iv
      # @param [ FFI::Pointer ] input_binary_p A pointer to a mongocrypt_binary_t
      #   object that wraps the data to be encrypted/decrypted
      # @param [ FFI::Pointer ] output_binary_p A pointer to a mongocrypt_binary_t
      #   object to which the encrypted/decrypted output will be written
      # @param [ FFI::Pointer ] response_length_p A pointer to an int32 to which
      #   the length of the output will be written
      # @param [ FFI::Pointer ] status_p A pointer to a mongocrypt_status_t
      #   object; if this method fails, an error message will be written to this status
      # @param [ true | false ] decrypt Whether this method is decrypting. Default is
      #   false, which means the method will create an encryption cipher by default
      #
      # @return [ true | false ] Whether the method succeeded. If false, retrieve the
      # error message from the mongocrypt_status_t object passed into the method.
      def aes(key_binary_p, iv_binary_p, input_binary_p, output_binary_p, response_length_p, status_p, decrypt: false)
        begin
          cipher = OpenSSL::Cipher::AES.new(256, :CBC)

          decrypt ? cipher.decrypt : cipher.encrypt
          cipher.key = Binary.from_pointer(key_binary_p).to_string
          cipher.iv = Binary.from_pointer(iv_binary_p).to_string
          cipher.padding = 0

          data = Binary.from_pointer(input_binary_p).to_string
          encrypted = cipher.update(data)

          Binary.from_pointer(output_binary_p).write(encrypted)

          response_length_p.write_int(encrypted.length)
        rescue => e
          handle_error(status_p, e)
          return false
        end

        true
      end
      module_function :aes

      # Crypto secure random function
      #
      # @param [ FFI::Pointer ] output_binary_p A pointer to a mongocrypt_binary_t
      #   object to which the encrypted/decrypted output will be written
      # @param [ Integer ] num_bytes The number of random bytes requested
      # @param [ FFI::Pointer ] status_p A pointer to a mongocrypt_status_t
      #   object; if this method fails, an error message will be written to this status
      #
      # @return [ true | false ] Whether the method succeeded. If false, retrieve the
      # error message from the mongocrypt_status_t object passed into the method.
      def random(output_binary_p, num_bytes, status_p)
        begin
          Binary.from_pointer(output_binary_p).write(SecureRandom.random_bytes(num_bytes))
        rescue => e
          handle_error(status_p, e)
          return false
        end

        true
      end
      module_function :random

      # An HMAC SHA-512 or SHA-256 function
      #
      # @param [ String ] The name of the digest, either "SHA256" or "SHA512"
      # @param [ FFI::Pointer ] key_binary_p A pointer to a mongocrypt_binary_t
      #   object that wraps the 32-byte encryption key
      # @param [ FFI::Pointer ] input_binary_p A pointer to a mongocrypt_binary_t
      #   object that wraps the data to be encrypted/decrypted
      # @param [ FFI::Pointer ] output_binary_p A pointer to a mongocrypt_binary_t
      #   object to which the encrypted/decrypted output will be written
      # @param [ FFI::Pointer ] status_p A pointer to a mongocrypt_status_t
      #   object; if this method fails, an error message will be written to this status
      #
      # @return [ true | false ] Whether the method succeeded. If false, retrieve the
      # error message from the mongocrypt_status_t object passed into the method.
      def hmac_sha(digest, key_binary_p, input_binary_p, output_binary_p, status_p)
        begin
          key = Binary.from_pointer(key_binary_p).to_string
          data = Binary.from_pointer(input_binary_p).to_string

          hmac = OpenSSL::HMAC.digest(digest, key, data)
          Binary.from_pointer(output_binary_p).write(hmac)
        rescue => e
          handle_error(status_p, e)
          return false
        end

        true
      end
      module_function :hmac_sha

      # A crypto hash (SHA-256) function
      #
      # @param [ FFI::Pointer ] input_binary_p A pointer to a mongocrypt_binary_t
      #   object that wraps the data to be encrypted/decrypted
      # @param [ FFI::Pointer ] output_binary_p A pointer to a mongocrypt_binary_t
      #   object to which the encrypted/decrypted output will be written
      # @param [ FFI::Pointer ] status_p A pointer to a mongocrypt_status_t
      #   object; if this method fails, an error message will be written to this status
      #
      # @return [ true | false ] Whether the method succeeded. If false, retrieve the
      # error message from the mongocrypt_status_t object passed into the method.
      def hash_sha256(input_binary_p, output_binary_p, status_p)
        begin
          data = Binary.from_pointer(input_binary_p).to_string

          hashed = Digest::SHA2.new(256).digest(data)
          Binary.from_pointer(output_binary_p).write(hashed)
        rescue => e
          handle_error(status_p, e)
          return false
        end
      end
      module_function :hash_sha256

      private

      # In the case of an error during cryptography, set the error message
      # of the specified status to the message of the runtime error
      def handle_error(status_p, e)
        status = Status.from_pointer(status_p)
        status.update(:error_client, 1, e.message)
      end
      module_function :handle_error
    end
  end
end