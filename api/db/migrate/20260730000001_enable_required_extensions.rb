# frozen_string_literal: true

# btree_gist は reservations の排他制約（booking_type_id WITH = と
# tstzrange WITH && を 1 つの GiST インデックスで扱う）に必須。
class EnableRequiredExtensions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "btree_gist"
  end
end
