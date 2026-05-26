# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# PLAN_0_1_0 Phase A — bootstrap Active Storage on the in-memory
# SQLite test connection without booting a full Rails::Application.
# Mirrors `vv-memory`'s pattern (which itself mirrors
# `vv-graph`'s). Needed because `vv-memory`'s episode model
# carries `has_one_attached :payload_blob`, which the
# `require "vv/memory"` chain triggers at class-definition time.
module Vv
  module Decision
    module SpecSupport
      module ActiveStorageEnvironment
        class << self
          def setup!
            require "active_record"
            require "openssl"
            require "global_id"
            GlobalID.app = "vvdec" unless GlobalID.app

            require "active_storage"

            require "zeitwerk"
            as_gem_root = Gem.loaded_specs["activestorage"].full_gem_path
            @as_loader ||= begin
              loader = ::Zeitwerk::Loader.new
              loader.push_dir(File.join(as_gem_root, "lib"))
              loader.push_dir(File.join(as_gem_root, "app/models"))
              loader.push_dir(File.join(as_gem_root, "app/controllers/concerns"))
              loader.do_not_eager_load(File.join(as_gem_root, "lib"))
              loader.do_not_eager_load(File.join(as_gem_root, "app/controllers/concerns"))
              %w[
                active_storage.rb active_storage/engine.rb active_storage/version.rb
                active_storage/gem_version.rb active_storage/deprecator.rb
                active_storage/errors.rb active_storage/log_subscriber.rb
                active_storage/fixture_set.rb active_storage/structured_event_subscriber.rb
              ].each { |f| loader.ignore(File.join(as_gem_root, "lib", f)) }
              loader.setup
              loader
            end

            unless ::ActiveStorage.respond_to?(:table_name_prefix)
              ::ActiveStorage.singleton_class.send(:define_method, :table_name_prefix) { "active_storage_" }
            end

            unless defined?(::Rails)
              stub = ::Module.new do
                def self.configuration
                  @configuration ||= begin
                    cfg = ::Object.new
                    def cfg.active_storage
                      @active_storage ||= begin
                        s = ::Object.new
                        def s.service; :test; end
                        s
                      end
                    end
                    cfg
                  end
                end

                def self.env; "test"; end
              end
              ::Object.const_set(:Rails, stub)
            end

            ::ActiveStorage::Attached::Model
            ::ActiveStorage::Reflection::ActiveRecordExtensions
            ::ActiveStorage::Reflection::ReflectionExtension

            unless ::ActiveRecord::Base.include?(::ActiveStorage::Attached::Model)
              ::ActiveRecord::Base.include(::ActiveStorage::Attached::Model)
            end
            unless ::ActiveRecord::Base.include?(::ActiveStorage::Reflection::ActiveRecordExtensions)
              ::ActiveRecord::Base.include(::ActiveStorage::Reflection::ActiveRecordExtensions)
            end
            unless ::ActiveRecord::Reflection.singleton_class.include?(::ActiveStorage::Reflection::ReflectionExtension)
              ::ActiveRecord::Reflection.singleton_class.prepend(::ActiveStorage::Reflection::ReflectionExtension)
            end

            ::ActiveStorage::Service::DiskService
            ::ActiveStorage::Blob
            ::ActiveStorage::Attachment
            ::ActiveStorage::VariantRecord

            unless ::ActiveStorage.const_defined?(:PurgeJob)
              ::ActiveStorage.const_set(:PurgeJob, ::Class.new do
                def self.perform_later(blob); blob.purge; end
              end)
            end

            ensure_schema!
            ensure_service!
          end

          def ensure_schema!
            conn = ::ActiveRecord::Base.connection
            return if conn.table_exists?(:active_storage_blobs)
            ::ActiveRecord::Schema.define do
              create_table :active_storage_blobs do |t|
                t.string   :key,          null: false
                t.string   :filename,     null: false
                t.string   :content_type
                t.text     :metadata
                t.string   :service_name, null: false
                t.bigint   :byte_size,    null: false
                t.string   :checksum
                t.datetime :created_at,   null: false
              end
              add_index :active_storage_blobs, :key, unique: true

              create_table :active_storage_attachments do |t|
                t.string     :name, null: false
                t.references :record, polymorphic: true, null: false, index: false
                t.references :blob,   null: false
                t.datetime   :created_at, null: false
              end
              add_index :active_storage_attachments,
                        %i[record_type record_id name blob_id],
                        name: "index_as_attachments_uniqueness",
                        unique: true

              create_table :active_storage_variant_records do |t|
                t.belongs_to :blob,            null: false, index: false
                t.string     :variation_digest, null: false
              end
              add_index :active_storage_variant_records,
                        %i[blob_id variation_digest],
                        unique: true
            end
          end

          def ensure_service!
            return if ::ActiveStorage::Blob.service.is_a?(::ActiveStorage::Service::DiskService)
            @storage_root ||= Dir.mktmpdir("vv-decision-storage-")
            service = ::ActiveStorage::Service::DiskService.new(root: @storage_root, public: false)
            service.name = :test
            ::ActiveStorage::Blob.services = ::ActiveStorage::Service::Registry.new({})
            ::ActiveStorage::Blob.services.send(:services)[:test] = service
            ::ActiveStorage::Blob.service = service
          end

          def reset!
            conn = ::ActiveRecord::Base.connection
            %i[active_storage_attachments active_storage_blobs active_storage_variant_records].each do |table|
              conn.execute("DELETE FROM #{table}") if conn.table_exists?(table)
            end
            FileUtils.rm_rf(@storage_root) if @storage_root && Dir.exist?(@storage_root)
            @storage_root = nil
          end
        end
      end
    end
  end
end
