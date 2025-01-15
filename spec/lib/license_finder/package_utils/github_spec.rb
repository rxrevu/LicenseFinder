# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LicenseFinder::GitHub do
  subject { described_class }

  describe '.definition' do
    let(:source) { 'api.github.com' }
    let(:package) { 'six' }
    let(:version) { '1.13.0' }
    let(:owner) { 'benjaminp' }
    let(:repo) { 'six' }
    let(:repo_url) { "https://github.com/#{owner}/#{repo}" }
    let(:successful_response_body) do
      JSON.generate(
        {
          name: 'LICENSE',
          url: "https://api.github.com/repos/#{owner}/#{repo}/contents/LICENSE?ref=main"
        }
      )
    end

    context 'when the default source is reachable' do
      before do
        stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/license")
          .to_return(status: 200, body: successful_response_body)
      end

      specify do
        expect(subject.license(repo_url)).to include(
          { 'name' => 'LICENSE',
            'url' => "https://api.github.com/repos/#{owner}/#{repo}/contents/LICENSE?ref=main" }
        )
      end
    end

    context 'when the response redirects to a different location' do
      let(:redirect_url) { 'https://api.github.com/repos/owner/repo/license' }

      before do
        stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/license")
          .to_return(status: 301, headers: { 'Location' => redirect_url })

        stub_request(:get, redirect_url)
          .to_return(status: 200, body: successful_response_body)
      end

      specify do
        expect(subject.license(repo_url)).to include(
          { 'name' => 'LICENSE',
            'url' => "https://api.github.com/repos/#{owner}/#{repo}/contents/LICENSE?ref=main" }
        )
      end
    end

    context 'when stuck in an infinite redirect loop' do
      before do
        url = "https://api.github.com/repos/#{owner}/#{repo}/license"

        11.times do |n|
          redirect_url = "#{url}#{n}"
          stub_request(:get, url)
            .to_return(status: 301, headers: { 'Location' => redirect_url })
          url = redirect_url
        end
      end

      it 'gives up after `n` attempts' do
        expect(subject.license(repo_url)).to be_empty
      end
    end

    context 'when the source is not reachable and --prepare_no_fail is not set' do
      before do
        stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/license")
          .to_timeout
      end

      it 'raises error' do
        expect { subject.license(repo_url) }.to raise_error(Net::OpenTimeout)
      end
    end

    context 'when the source is not reachable and --prepare_no_fail is set' do
      before do
        stub_request(:get, "https://api.github.com/repos/#{owner}/#{repo}/license")
          .to_timeout
        subject.instance_variable_set(:@prepare_no_fail, true)
      end

      it 'fails gracefully' do
        expect(subject.license(repo_url)).to be_empty
      end
    end
  end
end
