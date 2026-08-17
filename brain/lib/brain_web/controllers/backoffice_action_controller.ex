defmodule BrainWeb.BackofficeActionController do
  use BrainWeb, :controller

  alias Brain.Groups

  def approve(conn, %{"group_id" => group_id}) do
    case Groups.approve_group(group_id) do
      :ok ->
        conn
        |> put_flash(:info, "Group approved successfully")
        |> redirect(to: "/backoffice")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to approve: #{reason}")
        |> redirect(to: "/backoffice")
    end
  end

  def approve(conn, _params), do: redirect(conn, to: "/backoffice")

  def block(conn, %{"group_id" => group_id}) do
    case Groups.block_group(group_id) do
      :ok ->
        conn
        |> put_flash(:info, "Group blocked successfully")
        |> redirect(to: "/backoffice")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to block: #{reason}")
        |> redirect(to: "/backoffice")
    end
  end

  def block(conn, _params), do: redirect(conn, to: "/backoffice")

  def unblock(conn, %{"group_id" => group_id}) do
    case Groups.unblock_group(group_id) do
      :ok ->
        conn
        |> put_flash(:info, "Group unblocked successfully")
        |> redirect(to: "/backoffice")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to unblock: #{reason}")
        |> redirect(to: "/backoffice")
    end
  end

  def unblock(conn, _params), do: redirect(conn, to: "/backoffice")

  def delete(conn, %{"group_id" => group_id}) do
    case Groups.delete_group(group_id) do
      :ok ->
        conn
        |> put_flash(:info, "Group deleted successfully")
        |> redirect(to: "/backoffice")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to delete group: #{inspect(reason)}")
        |> redirect(to: "/backoffice")
    end
  end

  def delete(conn, _params), do: redirect(conn, to: "/backoffice")
end
