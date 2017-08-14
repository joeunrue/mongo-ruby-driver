require 'spec_helper'

describe Mongo::Operation::Write::Command::Delete do

  let(:write_concern) do
    Mongo::WriteConcern.get(WRITE_CONCERN)
  end

  let(:deletes) { [{:q => { :foo => 1 }, :limit => 1}] }
  let(:spec) do
    { :deletes       => deletes,
      :db_name       => authorized_collection.database.name,
      :coll_name     => authorized_collection.name,
      :write_concern => write_concern,
      :ordered       => true
    }
  end

  let(:op) { described_class.new(spec) }

  describe '#initialize' do

    context 'spec' do

      it 'sets the spec' do
        expect(op.spec).to eq(spec)
      end
    end
  end

  describe '#==' do

    context 'spec' do

      context 'when two ops have the same specs' do
        let(:other) { described_class.new(spec) }

        it 'returns true' do
          expect(op).to eq(other)
        end
      end

      context 'when two ops have different specs' do
        let(:other_deletes) { [{:q => { :bar => 1 }, :limit => 1}] }
        let(:other_spec) do
          { :deletes       => other_deletes,
            :db_name       => authorized_collection.database.name,
            :coll_name     => authorized_collection.name,
            :write_concern => write_concern,
            :ordered       => true
          }
        end
        let(:other) { described_class.new(other_spec) }

        it 'returns false' do
          expect(op).not_to eq(other)
        end
      end
    end
  end

  describe 'write concern' do

    context 'when write concern is not specified' do

      let(:spec) do
        { :deletes       => deletes,
          :db_name       => authorized_collection.database.name,
          :coll_name     => authorized_collection.name,
          :ordered       => true
        }
      end

      it 'does not include write concern in the selector' do
        expect(op.send(:selector)[:writeConcern]).to be_nil
      end
    end

    context 'when write concern is specified' do

      it 'includes write concern in the selector' do
        expect(op.send(:selector)[:writeConcern]).to eq(write_concern.options)
      end
    end
  end

  describe '#message' do

    context 'when the server supports OP_MSG', if: op_msg_enabled? do

      let(:expected_global_args) do
        {
            delete: TEST_COLL,
            ordered: true,
            writeConcern: write_concern.options,
            '$db' => TEST_DB
        }
      end

      let(:expected_payload_1) do
        {
            type: 1,
            payload: { identifier: 'deletes',
                       sequence: deletes
            }
        }
      end

      it 'creates the correct OP_MSG message' do
        expect(Mongo::Protocol::Msg).to receive(:new).with([:none], {}, expected_global_args, expected_payload_1)
        op.send(:message, authorized_primary)
      end

      context 'when the write concern is 0' do

        let(:write_concern) do
          Mongo::WriteConcern.get(w: 0)
        end

        it 'creates the correct OP_MSG message' do
          expect(Mongo::Protocol::Msg).to receive(:new).with([:more_to_come], {}, expected_global_args, expected_payload_1)
          op.send(:message, authorized_primary)
        end
      end
    end

    context 'when the server does not support OP_MSG' do

      let(:expected_selector) do
        {
            :delete        => authorized_collection.name,
            :deletes       => deletes,
            :writeConcern => write_concern.options,
            :ordered       => true
        }
      end

      it 'creates the correct query wire protocol message', unless: op_msg_enabled? do
        expect(Mongo::Protocol::Query).to receive(:new).with(authorized_collection.database.name,
                                                             '$cmd',
                                                             expected_selector,
                                                             { limit: -1 } )
        op.send(:message, authorized_primary)
      end
    end
  end
end
