require 'rails_helper'

RSpec.describe SchoolCalendarSetterByStepWorker, type: :worker do
  let(:entity) { Entity.first }

  it 'raises error when does not have worker state with current jid' do
    subject.jid = 123

    expect do
      subject.perform(entity.id, '', 1)
    end.to raise_error ActiveRecord::RecordNotFound
  end

  it 'does not raise error when has worker state with current jid' do
    worker_state = nil

    entity.using_connection do
      worker_state = create(:worker_state)
    end

    subject.jid = worker_state.job_id

    expect do
      subject.perform(entity.id, '', 1)
    end.to_not raise_error
  end
end
