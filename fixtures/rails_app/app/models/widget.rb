class Widget < ActiveRecord::Base
  def active_widget_offers
    WidgetOffer.all
  end
end
