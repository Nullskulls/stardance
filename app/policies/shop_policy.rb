class ShopPolicy < ApplicationPolicy
  def my_orders?
    signed_in_any?
  end

  def cancel_order?
    signed_in_any?
  end

  def order?
    signed_in_any?
  end

  def create_order?
    signed_in_any?
  end
end
