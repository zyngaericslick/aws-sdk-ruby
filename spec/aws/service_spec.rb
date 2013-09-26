# Copyright 2011-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'spec_helper'

module Aws
  describe Service do

    let(:api_older) {
      api = Seahorse::Model::Api.new
      api.version = '2013-01-01'
      api
    }

    let(:api_newer) {
      api = Seahorse::Model::Api.new
      api.version = '2013-02-02'
      api
    }

    let(:apis) { [api_newer, api_older] }

    describe 'add_version' do

      it 'registers a new API version' do
        svc = Class.new(Service)
        svc.add_version('2013-01-02', 'path/to/api.json')
        expect(svc.api_versions).to eq(['2013-01-02'])
      end

      it 'can be called multiple times' do
        svc = Class.new(Service)
        svc.add_version('2013-02-03', 'path/to/api2.json')
        svc.add_version('2013-01-02', 'path/to/api1.json')
        expect(svc.api_versions).to eq(['2013-01-02', '2013-02-03'])
        expect(svc.latest_api_version).to eq('2013-02-03')
      end

      it 'treats the newest api version as the default' do
        svc = Class.new(Service)
        svc.add_version('2013-02-03', 'path/to/api2.json')
        svc.add_version('2013-01-02', 'path/to/api1.json')
        expect(svc.default_api_version).to eq(svc.latest_api_version)
      end

    end

    describe '.add_plugin' do

      it 'adds a plugin to each versioned client class' do
        plugin = double('plugin')
        svc = Service.define(:name, apis)
        svc.add_plugin(plugin)
        svc.versioned_clients.each do |klass|
          expect(klass.plugins).to include(plugin)
        end
      end

    end

    describe '.remove_plugin' do

      it 'removes a plugin from each versioned client class' do
        plugin = double('plugin')
        svc = Service.define(:name, apis)
        svc.add_plugin(plugin)
        svc.remove_plugin(plugin)
        svc.versioned_clients.each do |klass|
          expect(klass.plugins).not_to include(plugin)
        end
      end

    end

    describe '.define' do

      it 'defines a new client factory' do
        svc = Service.define(:identifier)
        expect(svc.ancestors).to include(Service)
      end

      it 'populates the method name' do
        svc = Service.define(:identifier)
        expect(svc.identifier).to eq(:identifier)
      end

      it 'accepts apis as a path to a translated api' do
        api = 'apis/S3-2006-03-01.json'
        svc = Service.define(:name, [api])
        client_class = svc.const_get(:V20060301)
        allow(client_class).to receive(:name).and_return('Aws::Svc::V20060301')
        client = client_class.new
        expect(client.config.api.version).to eq('2006-03-01')
      end

      it 'accepts apis as a path to an un-translated api' do
        api = 'apis-src/autoscaling-2011-01-01.json'
        svc = Service.define(:name, [api])
        client_class = svc.const_get(:V20110101)
        allow(client_class).to receive(:name).and_return('Aws::Svc::V20060301')
        client = client_class.new
        expect(client.config.api.version).to eq('2011-01-01')
      end

      it 'accepts apis as Seahorse::Model::Api' do
        api = Seahorse::Model::Api.new
        api.version = '2013-01-02'
        svc = Service.define(:name, [api])
        expect(svc.const_get(:V20130102).new.config.api).to be(api)
      end

    end

    describe 'new' do

      after(:each) do
        Aws.config = {}
      end

      it 'builds the client class with the latest api version by default' do
        svc = Service.define(:name, apis)
        expect(svc.new.config.api).to be(api_newer)
        expect(svc.new).to be_kind_of(svc.const_get(:V20130202))
      end

      it 'defaults to the global configured version for the client' do
        Aws.config[:client_name] = { api_version: api_older.version }
        svc = Service.define(:client_name, apis)
        expect(svc.new.config.api).to be(api_older)
        expect(svc.new).to be_kind_of(svc.const_get(:V20130101))
      end

      it 'accepts the api verison as a constructor option' do
        Aws.config[:client_name] = { api_version: api_older.version }
        svc = Service.define(:client_name, apis)
        client = svc.new(api_version: api_newer.version)
        expect(client.config.api).to be(api_newer)
        expect(client).to be_kind_of(svc.const_get(:V20130202))
      end

      it 'uses the closest version without going over' do
        Aws.config[:api_version] = '2013-01-15'
        svc = Service.define(:client_name, apis)
        expect(svc.new.class).to be(svc.const_get(:V20130101))
      end

      it 'raises an error if the global version is preceedes all versions' do
        Aws.config[:api_version] = '2000-00-00'
        svc = Service.define(:client_name, apis)
        expect {
          expect(svc.new)
        }.to raise_error(Errors::NoSuchApiVersionError, /2000-00-00/)
      end

      it 'merges global defaults options when constructing the client' do
        # shared default disabled
        Aws.config = { http_wire_trace: false }
        expect(Aws::EC2.new.config.http_wire_trace).to be(false)
        expect(Aws::S3.new.config.http_wire_trace).to be(false)
        # shared default enabled
        Aws.config = { http_wire_trace: true }
        expect(Aws::EC2.new.config.http_wire_trace).to be(true)
        expect(Aws::S3.new.config.http_wire_trace).to be(true)
        # default enabled, s3 disables
        Aws.config = { http_wire_trace: true, s3: { http_wire_trace: false } }
        expect(Aws::EC2.new.config.http_wire_trace).to be(true)
        expect(Aws::S3.new.config.http_wire_trace).to be(false)
      end

    end

    describe 'client classes' do

      it 'returns each client class from .versioned_clients' do
        svc = Service.define(:name, apis)
        expect(svc.versioned_clients).to eq([
          svc.const_get(:V20130101),
          svc.const_get(:V20130202),
        ])
      end

      it 'defines clients for each api version' do
        target = Seahorse::Client::Base
        c = Service.define(:name, apis)
        expect(c.const_get(:V20130101).ancestors).to include(target)
      end

      it 'raises an error if the asked for client class does not exist' do
        svc = Service.define(:name)
        expect {
          svc.const_get(:V20001012)
        }.to raise_error(Errors::NoSuchApiVersionError)
      end

      it 'raises a helpful error when the api is not defined' do
        svc = Service.define(:name)
        expect {
          svc.const_get(:V20001012)
        }.to raise_error("API 2000-10-12 not defined for #{svc.name}")
      end

      it 'does not interfere with const missing' do
        svc = Service.define(:name)
        expect {
          svc.const_get(:FooBar)
        }.to raise_error(NameError, /uninitialized constant/)
      end

    end

    describe 'Errors module' do

      let(:svc) { Service.define(:name) }

      let(:errors) { svc.const_get(:Errors) }

      it 'has an errors module' do
        expect(svc.const_defined?(:Errors)).to be(true)
      end

      it 'lazily creates error classes' do
        err_class = errors.const_get(:AbcXyz)
        expect(err_class.new).to be_kind_of(Errors::ServiceError)
      end

      it 'allows you to create error classes named like Ruby classes' do
        error_class = Aws::Errors.error_class('S3', 'Range')
        expect(error_class).not_to be(Range)
        expect(error_class).to be(Aws::S3::Errors::Range)
        expect(error_class.ancestors).to include(Errors::ServiceError)
      end

    end
  end
end