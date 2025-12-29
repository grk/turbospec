require 'rails_helper'

RSpec.describe WidgetsHelper, type: :helper do
  fixtures :widgets, :widget_offers

  describe "#widget_offers" do
    let(:widget) { widgets(:high_power) }
    let(:offer) { widget_offers(:basic_offer) }

    it "uses the fixture instead of the helper" do
      # This will fail with NoMethodError if shadowing occurs
      expect { widget.active_widget_offers }.not_to raise_error
    end
  end
end
