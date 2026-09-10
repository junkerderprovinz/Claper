defmodule ClaperWeb.UserSessionControllerTest do
  use ClaperWeb.ConnCase, async: true

  import Claper.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/log_in" do
    test "renders log in page", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in")
      response = html_response(conn, 200)
      assert response =~ "Email address"
    end

    test "redirects if already logged in", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/users/log_in")
      assert redirected_to(conn) == "/events"
    end

    test "logs the user back in to the page they came from", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/log_in?#{[return_to: "/e/abcd1234"]}")

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/e/abcd1234"
    end

    test "ignores a return path pointing at another host", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/log_in?#{[return_to: "https://evil.example.com/phish"]}")

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/events"
    end

    test "ignores a protocol relative return path", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/log_in?#{[return_to: "//evil.example.com/phish"]}")

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/events"
    end

    test "ignores a return path holding a tab", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/log_in?#{[return_to: "/\t/evil.example.com/phish"]}")

      refute get_session(conn, :user_return_to)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/events"
    end

    test "ignores a return path holding an escaped tab", %{conn: conn, user: user} do
      conn = get(conn, ~p"/users/log_in?#{[return_to: "/%09/evil.example.com/phish"]}")

      refute get_session(conn, :user_return_to)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/events"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == "/"
      refute get_session(conn, :user_token)
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == "/"
      refute get_session(conn, :user_token)
    end
  end
end
