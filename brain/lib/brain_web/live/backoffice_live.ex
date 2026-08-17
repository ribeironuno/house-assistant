defmodule BrainWeb.BackofficeLive do
  use BrainWeb, :live_view

  alias Brain.Groups
  alias Brain.Repo
  alias Brain.Groups.Group

  @impl true
  def mount(_params, session, socket) do
    if Map.has_key?(session, "backoffice_user") do
      groups = fetch_groups()
      {:ok, assign(socket, groups: groups, filter: "all")}
    else
      {:ok, redirect(socket, to: "/backoffice/login")}
    end
  end

  @impl true
  def handle_event("filter", %{"status" => filter}, socket) do
    {:noreply, assign(socket, filter: filter)}
  end

  @impl true
  def handle_event("approve", %{"id" => group_id}, socket) do
    case Groups.approve_group(group_id) do
      :ok ->
        {:noreply, assign(socket, groups: fetch_groups())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to approve: #{reason}")}
    end
  end

  @impl true
  def handle_event("block", %{"id" => group_id}, socket) do
    case Groups.block_group(group_id) do
      :ok ->
        {:noreply, assign(socket, groups: fetch_groups())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to block: #{reason}")}
    end
  end

  @impl true
  def handle_event("unblock", %{"id" => group_id}, socket) do
    case Groups.unblock_group(group_id) do
      :ok ->
        {:noreply, assign(socket, groups: fetch_groups())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to unblock: #{reason}")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => group_id}, socket) do
    case Groups.delete_group(group_id) do
      :ok ->
        {:noreply, assign(socket, groups: fetch_groups())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete: #{reason}")}
    end
  end

  @impl true
  def handle_event("add_admin", %{"group_id" => group_id, "number" => number}, socket) do
    number = String.trim(number)

    if number == "" do
      {:noreply, put_flash(socket, :error, "Admin number cannot be empty")}
    else
      case Groups.add_admin(group_id, number) do
        {:ok, _admins} ->
          {:noreply, assign(socket, groups: fetch_groups()) |> put_flash(:info, "Admin added")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to add admin: #{reason}")}
      end
    end
  end

  @impl true
  def handle_event("remove_admin", %{"group_id" => group_id, "number" => number}, socket) do
    case Groups.remove_admin(group_id, number) do
      {:ok, _admins} ->
        {:noreply, assign(socket, groups: fetch_groups()) |> put_flash(:info, "Admin removed")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to remove admin: #{reason}")}
    end
  end

  defp fetch_groups do
    Repo.all(Group) |> Enum.sort_by(& &1.inserted_at, :desc)
  end

  defp filtered_groups(groups, "all"), do: groups
  defp filtered_groups(groups, filter), do: Enum.filter(groups, &(&1.status == filter))

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :visible_groups, filtered_groups(assigns.groups, assigns.filter))

    ~H"""
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
      <h1>Group Management</h1>
      <a href="/backoffice/logout" style="color: #e53e3e; text-decoration: none; font-weight: 500; font-size: 0.9rem;">
        Logout →
      </a>
    </div>

    <div style="margin-bottom: 1.2rem; display: flex; gap: 0.5rem; flex-wrap: wrap;">
      <%= for {label, status_key} <- [
        {"All", "all"},
        {"Waiting Approval", "waiting_approval"},
        {"Pending", "pending"},
        {"Active", "active"},
        {"Left", "left"},
        {"Blocked", "blocked"}
      ] do %>
        <button
          phx-click="filter"
          phx-value-status={status_key}
          style={if @filter == status_key, do: "background: #3182ce; color: white;", else: "background: #e2e8f0; color: #2d3748;"}
        >
          <%= label %>
        </button>
      <% end %>
    </div>

    <table>
      <thead>
        <tr>
          <th>Group Name</th>
          <th>Group ID</th>
          <th>Status</th>
          <th>Admin Numbers</th>
          <th>Created</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <%= for group <- @visible_groups do %>
          <tr>
            <td style="font-weight: 600;"><%= group.name || "—" %></td>
            <td style="font-family: monospace; font-size: 0.85rem;"><%= group.group_id %></td>
            <td>
              <span class={"status status-#{group.status}"}><%= group.status %></span>
            </td>
            <td>
              <div style="display: flex; flex-direction: column; gap: 0.4rem;">
                <%= if group.admin_numbers && group.admin_numbers != [] do %>
                  <%= for num <- group.admin_numbers do %>
                    <span style="display: flex; align-items: center; gap: 0.5rem; font-family: monospace; font-size: 0.85rem;">
                      <%= num %>
                      <form phx-submit="remove_admin" phx-value-group_id={group.group_id} phx-value-number={num} style="display: inline;">
                        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                        <button type="submit" style="background: none; border: none; color: #e53e3e; cursor: pointer; padding: 0; font-size: 0.85rem;" phx-confirm="Remove this admin number?">✕</button>
                      </form>
                    </span>
                  <% end %>
                <% else %>
                  <span style="color: #a0aec0; font-size: 0.85rem;">(none)</span>
                <% end %>
                <%= if group.status in ["pending", "active"] do %>
                  <form phx-submit="add_admin" phx-value-group_id={group.group_id} style="display: flex; gap: 0.4rem; max-width: 350px;">
                    <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                    <input type="text" name="number" placeholder="5511999999999@s.whatsapp.net" style="flex: 1; padding: 0.4rem 0.6rem; border: 1px solid #cbd5e0; border-radius: 4px; font-size: 0.85rem;" />
                    <button type="submit" style="padding: 0.4rem 0.8rem; background: #38a169; color: white; border: none; border-radius: 4px; font-size: 0.85rem; cursor: pointer;">Add</button>
                  </form>
                <% end %>
              </div>
            </td>
            <td><%= Calendar.strftime(group.inserted_at, "%Y-%m-%d %H:%M") %></td>
            <td class="actions">
              <%= if group.status == "waiting_approval" do %>
                <form action="/backoffice/groups/approve" method="post" style="display: inline;">
                  <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                  <input type="hidden" name="group_id" value={group.group_id} />
                  <button type="submit" class="btn-approve" phx-click="approve" phx-value-id={group.group_id}>
                    Approve
                  </button>
                </form>
              <% end %>

              <%= if group.status in ["pending", "active", "left", "waiting_approval"] do %>
                <form action="/backoffice/groups/block" method="post" style="display: inline;">
                  <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                  <input type="hidden" name="group_id" value={group.group_id} />
                  <button type="submit" class="btn-block" phx-click="block" phx-value-id={group.group_id}>
                    Block
                  </button>
                </form>
              <% end %>

              <%= if group.status == "blocked" do %>
                <form action="/backoffice/groups/unblock" method="post" style="display: inline;">
                  <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                  <input type="hidden" name="group_id" value={group.group_id} />
                  <button type="submit" class="btn-unblock" phx-click="unblock" phx-value-id={group.group_id}>
                    Unblock
                  </button>
                </form>
              <% end %>

              <form action="/backoffice/groups/delete" method="post" style="display: inline;" onsubmit="return confirm('Are you sure you want to delete this group? Future messages will treat it as a new group.');">
                <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
                <input type="hidden" name="group_id" value={group.group_id} />
                <button type="submit" class="btn-delete" phx-click="delete" phx-value-id={group.group_id} phx-confirm="Are you sure you want to delete this group? Future messages will treat it as a new group.">
                  Delete
                </button>
              </form>
            </td>
          </tr>
        <% end %>
        <%= if Enum.empty?(@visible_groups) do %>
          <tr>
            <td colspan="6" style="text-align: center; color: #718096; padding: 2rem;">
              No groups found.
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end
end
