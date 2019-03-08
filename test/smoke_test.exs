defmodule JSONAPI.SmokeTest do
  use ExUnit.Case, async: false

  alias JSONAPI.{Config, Serializer}

  defmodule UserView do
    use JSONAPI.View

    def fields, do: [:username, :first_name, :last_name]
    def type, do: "user"

    def relationships do
      [company: JSONAPI.SmokeTest.CompanyView]
    end
  end

  defmodule CompanyView do
    use JSONAPI.View

    def fields, do: [:name]
    def type, do: "company"

    def relationships do
      [industry: JSONAPI.SmokeTest.IndustryView]
    end
  end

  defmodule IndustryView do
    use JSONAPI.View

    def fields, do: [:name]
    def type, do: "industry"

    def relationships, do: []
  end

  defmodule PostView do
    use JSONAPI.View

    def fields, do: [:text, :body, :full_description, :inserted_at]
    def meta(data, _conn), do: %{meta_text: "meta_#{data[:text]}"}
    def type, do: "mytype"

    def relationships do
      [
        author: {JSONAPI.SmokeTest.UserView, :include},
        best_comments: {JSONAPI.SmokeTest.CommentView, :include}
      ]
    end

    def links(data, conn) do
      %{
        next: url_for_pagination(data, conn, %{cursor: "some-string"})
      }
    end
  end

  defmodule CommentView do
    use JSONAPI.View

    def fields, do: [:text]
    def type, do: "comment"

    def relationships do
      [user: {JSONAPI.SmokeTest.UserView, :include}]
    end
  end

  setup do
    Application.put_env(:jsonapi, :field_transformation, :underscore)

    on_exit(fn ->
      Application.delete_env(:jsonapi, :field_transformation)
    end)

    {:ok, []}
  end

  test "no includes, no relationship data available" do
    data = %{
      id: 123,
      first_name: "Jeff",
      last_name: "Smith",
      username: "j.smith"
    }

    assert %{
      data: %{
        id: "123",
        type: "user",
        attributes: %{
          first_name: data.first_name,
          last_name: data.last_name,
          username: data.username,
        },
        relationships: %{
        },
        links: %{
          self: "/user/123"
        }
      },
      included: [],
      links: %{
        self: "/user/123"
      }
    } == Serializer.serialize(UserView, data, nil, nil)
  end

  test "no includes, relationship data available" do
    data = %{
      id: 123,
      first_name: "Jeff",
      last_name: "Smith",
      username: "j.smith",
      company: %{id: 2, name: "acme"}
    }

    assert %{
      data: %{
        id: "123",
        type: "user",
        attributes: %{
          first_name: data.first_name,
          last_name: data.last_name,
          username: data.username,
        },
        relationships: %{
          company: %{
            data: %{
              id: "2",
              type: "company"
            },
            links: %{
              self: "/user/123/relationships/company",
              related: "/company/2"
            }
          }
        },
        links: %{
          self: "/user/123"
        }
      },
      included: [],
      links: %{
        self: "/user/123"
      }
    } == Serializer.serialize(UserView, data, nil, nil)
  end

  test "request to sideload data" do
    data = %{
      id: 123,
      first_name: "Jeff",
      last_name: "Smith",
      username: "j.smith",
      company: %{id: 2, name: "acme"}
    }

    conn = %Plug.Conn{
      assigns: %{
        jsonapi_query: %Config{
          include: [:company]
        }
      }
    }

    assert %{
      data: %{
        id: "123",
        type: "user",
        attributes: %{
          first_name: data.first_name,
          last_name: data.last_name,
          username: data.username,
        },
        relationships: %{
          company: %{
            data: %{
              id: "2",
              type: "company"
            },
            links: %{
              related: "http://www.example.com/company/2",
              self: "http://www.example.com/user/123/relationships/company"
            }
          }
        },
        links: %{
          self: "http://www.example.com/user/123"
        }
      },
      included: [
        %{
          attributes: %{
            name: data.company.name
          },
          id: "2",
          links: %{
            self: "http://www.example.com/company/2"
          },
          relationships: %{},
          type: "company"
        }
      ],
      links: %{
        self: "http://www.example.com/user/123"
      }
    } == Serializer.serialize(UserView, data, conn, nil)
  end

  test "with meta data" do
    data = %{
      id: 4,
      text: "Midnight Lightning",
      body: "Some day I shall climb thee",
      full_description: "Days dreaming about Yosemite",
      inserted_at: ~N[2019-03-06 09:24:00]
    }

    meta = %{
      total_pages: 12
    }

    expected_query = URI.encode_query(%{"page[cursor]": "some-string"})

    assert %{
      data: %{
        attributes: %{
          body: data.body,
          full_description: data.full_description,
          text: data.text,
          inserted_at: data.inserted_at
        },
        id: "4",
        type: "mytype",
        links: %{
          next: "/mytype/4?#{expected_query}",
          self: "/mytype/4"
        },
        meta: %{
          meta_text: "meta_Midnight Lightning"
        },
        relationships: %{}
      },
      included: [],
      links: %{
        next: "/mytype/4?#{expected_query}",
        self: "/mytype/4"
      },
      meta: %{
        total_pages: 12
      }
    } == Serializer.serialize(PostView, data, nil, meta)
  end

  test "has many" do
    data = [
      %{
        id: 123,
        first_name: "Jeff",
        last_name: "Smith",
        username: "j.smith"
      },
      %{
        id: 456,
        first_name: "Jane",
        last_name: "Doe",
        username: "j.doe"
      }
    ]

    assert %{
      data: [
        %{
          attributes: %{
            first_name: "Jeff",
            last_name: "Smith",
            username: "j.smith"
          },
          id: "123",
          links: %{self: "/user/123"},
          relationships: %{},
          type: "user"
        },
        %{
          attributes: %{
            first_name: "Jane",
            last_name: "Doe",
            username: "j.doe"
          },
          id: "456",
          links: %{self: "/user/456"},
          relationships: %{},
          type: "user"
        }
      ],
      included: [],
      links: %{self: "/user"}
    } == Serializer.serialize(UserView, data, nil, nil)
  end
end
