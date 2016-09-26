# frozen_string_literal: true
require 'spec_helper'

RSpec.describe 'Active Record Validations' do
  include_context 'ActiveRecord Setup'
  subject { ActiveRecordArticle.find_by_title 'new1' }

  describe 'Outside of the transition' do
    it { is_expected.to be_valid }
  end

  describe 'During the transition' do
    describe 'When the validation rules are met' do
      before do
        subject.body = 'Some Body'
      end
      it 'should be able to transition' do
        expect(subject.can_transition?(:accept)).to be_truthy
      end

      it 'should succeed the transition' do
        expect(subject.accept!).to be_truthy
        subject.reload
        expect(subject).to be_accepted
      end
    end

    describe 'When validation rules are not met' do
      before do
        subject.body = nil
      end
      it 'should NOT be able to transition' do
        expect(subject.can_transition?(:accept)).to be_falsey
      end

      it 'should clear the errors after running' do
        subject.can_transition?(:accept)
        expect(subject.errors).to be_empty
      end

      it 'should NOT succeed the transition' do
        expect(subject.accept!).to be_falsey
        subject.reload
        expect(subject).not_to be_accepted
      end

      it { is_expected.to be_valid }

      it 'should have the errors on the object' do
        subject.accept!
        expect(subject.errors).not_to be_empty
        expect(subject).not_to be_valid
      end

      it 'should re-validate the object after some manipulation.' do
        subject.accept!
        expect(subject.errors).not_to be_empty
        expect(subject).not_to be_valid
        subject.body = subject.body
        expect(subject).to be_valid
      end
    end
  end

  before do
    ActiveRecord::Schema.define do
      create_table :active_record_articles do |t|
        t.string :title
        t.string :body
        t.string :blame_reason
        t.string :reject_reason
        t.string :workflow_state
      end
    end

    exec "INSERT INTO active_record_articles(title, body, blame_reason, reject_reason, workflow_state) VALUES('new1', NULL, NULL, NULL, 'new')"
    exec "INSERT INTO active_record_articles(title, body, blame_reason, reject_reason, workflow_state) VALUES('new2', 'some content', NULL, NULL, 'new')"
    exec "INSERT INTO active_record_articles(title, body, blame_reason, reject_reason, workflow_state) VALUES('accepted1', 'some content', NULL, NULL, 'accepted')"
  end
  # Transition based validation
  # ---------------------------
  # If you are using ActiveRecord you might want to define different validations
  # for different transitions. There is a `validates_presence_of` hook that let's
  # you specify the attributes that need to be present for an successful transition.
  # If the object is not valid at the end of the transition event the transition
  # is halted and a TransitionHaltedError exception is thrown.
  #
  # Here is a sample that illustrates how to use the presence validation:
  # (use case suggested by http://github.com/southdesign)
  class ActiveRecordArticle < ActiveRecord::Base
    include Workflow

    [:title, :body].each do |attr|
      validates attr, presence: true, if: :transitioning_via_event_accept?
    end

    [:title, :body, :blame_reason].each do |attr|
      validates attr, presence: true, if: :transitioning_via_event_blame?
    end

    halt_transition_unless_valid!

    workflow do
      state :new do
        on :accept, to: :accepted
        on :reject, to: :rejected
      end
      state :accepted do
        on :blame, to: :blamed
        on :delete, to: :deleted
      end
      state :rejected do
        on :delete, to: :deleted
      end
      state :blamed do
        on :delete, to: :deleted
      end
      state :deleted do
        on :accept, to: :accepted
      end
    end
  end
end