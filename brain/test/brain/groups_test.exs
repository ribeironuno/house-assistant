defmodule Brain.GroupsTest do
  use BrainWeb.ConnCase, async: true

  alias Brain.Repo
  alias Brain.Groups
  alias Brain.Groups.Group
  alias Brain.Pantry
  alias Brain.Pantry.Item, as: PantryItem
  alias Brain.ShoppingList
  alias Brain.ShoppingList.Item, as: ShoppingItem

  @group_id "120363000000000001@g.us"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "handle_join/1" do
    test "unknown group is registered as pending and bot introduces itself" do
      assert {:reply, intro} = Groups.handle_join(@group_id)
      assert intro == Groups.intro_text()

      group = Repo.get(Group, @group_id)
      assert group.status == "pending"
      assert group.group_id == @group_id
    end

    test "active group is ignored (no re-introduction)" do
      Groups.activate(@group_id)

      assert :ignore = Groups.handle_join(@group_id)
      assert Repo.get(Group, @group_id).status == "active"
    end

    test "left group is re-registered as pending when re-added" do
      Groups.mark_left(@group_id)

      assert {:reply, intro} = Groups.handle_join(@group_id)
      assert intro == Groups.intro_text()
      assert Repo.get(Group, @group_id).status == "pending"
    end
  end

  describe "handle_message/3" do
    test "unknown group is registered as pending and bot introduces itself" do
      assert {:reply, intro} = Groups.handle_message(@group_id, "adiciona leite", "user_1")
      assert intro == Groups.intro_text()
      assert Repo.get(Group, @group_id).status == "pending"
    end

    test "pending group answering 'sim' is activated" do
      Groups.register_pending(@group_id)

      assert {:reply, reply} = Groups.handle_message(@group_id, "sim", "user_1")
      assert reply == Groups.activated_text()
      assert Repo.get(Group, @group_id).status == "active"
    end

    test "pending group answering 'sim' with trailing punctuation is activated" do
      Groups.register_pending(@group_id)

      assert {:reply, _} = Groups.handle_message(@group_id, "sim!", "user_1")
      assert Repo.get(Group, @group_id).status == "active"
    end

    test "pending group answering 'SIM' (case insensitive) is activated" do
      Groups.register_pending(@group_id)

      assert {:reply, _} = Groups.handle_message(@group_id, "SIM", "user_1")
      assert Repo.get(Group, @group_id).status == "active"
    end

    test "pending group answering 'não' is marked left and asked to leave" do
      Groups.register_pending(@group_id)

      assert {:leave, reply} = Groups.handle_message(@group_id, "não", "user_1")
      assert reply == Groups.farewell_text()
      assert Repo.get(Group, @group_id).status == "left"
    end

    test "pending group answering 'não quero' is marked left" do
      Groups.register_pending(@group_id)

      assert {:leave, _} = Groups.handle_message(@group_id, "não quero", "user_1")
      assert Repo.get(Group, @group_id).status == "left"
    end

    test "pending group sending unrelated text is asked again and stays pending" do
      Groups.register_pending(@group_id)

      assert {:reply, reply} = Groups.handle_message(@group_id, "olá bot", "user_1")
      assert reply == Groups.ask_again_text()
      assert Repo.get(Group, @group_id).status == "pending"
    end

    test "active group messages proceed" do
      Groups.activate(@group_id)

      assert :proceed = Groups.handle_message(@group_id, "adiciona leite", "user_1")
      assert Repo.get(Group, @group_id).status == "active"
    end

    test "left group messages are ignored" do
      Groups.mark_left(@group_id)

      assert :ignore = Groups.handle_message(@group_id, "adiciona leite", "user_1")
    end
  end

  describe "registration helpers" do
    test "register_pending is idempotent" do
      Groups.register_pending(@group_id)
      Groups.register_pending(@group_id)

      assert length(Repo.all(Group)) == 1
      assert Repo.get(Group, @group_id).status == "pending"
    end

    test "activate is idempotent" do
      Groups.activate(@group_id)
      Groups.activate(@group_id)

      assert length(Repo.all(Group)) == 1
      assert Repo.get(Group, @group_id).status == "active"
    end

    test "mark_left updates an existing active group" do
      Groups.activate(@group_id)
      Groups.mark_left(@group_id)

      assert length(Repo.all(Group)) == 1
      assert Repo.get(Group, @group_id).status == "left"
    end

    test "active?/1 reflects the stored status" do
      refute Groups.active?(@group_id)

      Groups.activate(@group_id)
      assert Groups.active?(@group_id)
    end
  end

  describe "foreign key constraints" do
    test "deleting a group cascades to its shopping, pantry, and reminder records" do
      Groups.activate(@group_id)
      ShoppingList.add("leite", @group_id, "user_1")
      Pantry.add_many(["arroz"], @group_id, "user_1")

      Repo.insert(
        Brain.Reminders.Reminder.changeset(%Brain.Reminders.Reminder{}, %{
          text: "pagar conta",
          remind_at: DateTime.add(DateTime.utc_now(), 60, :second),
          created_by: "user_1",
          group_id: @group_id
        })
      )

      Repo.delete!(Repo.get(Group, @group_id))

      assert Repo.all(ShoppingItem) == []
      assert Repo.all(PantryItem) == []
      assert Repo.all(Brain.Reminders.Reminder) == []
    end

    test "child records cannot be created for a non-existent group" do
      refute Repo.get(Group, @group_id)

      assert {:error, _changeset} =
               Repo.insert(
                 ShoppingItem.changeset(%ShoppingItem{}, %{
                   name: "leite",
                   group_id: @group_id
                 })
               )

      assert Repo.all(ShoppingItem) == []
    end
  end
end
