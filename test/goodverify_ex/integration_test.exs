defmodule GoodverifyEx.IntegrationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias GoodverifyEx.Schemas

  setup :verify_on_exit!

  @client GoodverifyEx.client(base_url: "https://api.goodverify.com", api_key: "sk_test_123")

  defp json_response(status, body) do
    {:ok, %Req.Response{status: status, body: body}}
  end

  # ── Health ──────────────────────────────────────────────────────────

  describe "health/1" do
    test "returns healthy status" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] == "https://api.goodverify.com/api/v1/health"
        assert opts[:headers] == [{"authorization", "Bearer sk_test_123"}]

        json_response(200, %{
          "status" => "healthy",
          "timestamp" => "2026-02-11T12:00:00Z"
        })
      end)

      assert {:ok, result} = GoodverifyEx.health(@client)
      assert %Schemas.HealthResponse{} = result
      assert result.status == "healthy"
      assert result.timestamp == "2026-02-11T12:00:00Z"
    end

    test "returns degraded status as error" do
      expect(Req, :request, fn _opts ->
        json_response(503, %{
          "status" => "degraded",
          "timestamp" => "2026-02-11T12:00:00Z"
        })
      end)

      assert {:error, %{status: 503, body: body}} = GoodverifyEx.health(@client)
      assert body["status"] == "degraded"
    end

    test "does not send auth header when api_key is nil" do
      client = GoodverifyEx.client(base_url: "https://api.goodverify.com")

      expect(Req, :request, fn opts ->
        assert opts[:headers] == []
        json_response(200, %{"status" => "healthy", "timestamp" => "now"})
      end)

      assert {:ok, _result} = GoodverifyEx.health(client)
    end
  end

  # ── Usage ───────────────────────────────────────────────────────────

  describe "usage/1" do
    test "returns usage statistics" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] == "https://api.goodverify.com/api/v1/usage"

        json_response(200, %{
          "plan" => "free",
          "billing_period" => %{
            "start" => "2026-02-01T00:00:00Z",
            "end" => "2026-02-28T23:59:59Z"
          },
          "usage" => %{
            "verifications_used" => 25,
            "verifications_limit" => 100
          },
          "credits" => %{
            "balance" => 75,
            "used_this_period" => 25
          },
          "rate_limit" => %{
            "requests_per_minute" => 100
          }
        })
      end)

      assert {:ok, result} = GoodverifyEx.usage(@client)
      assert %Schemas.UsageResponse{} = result
      assert result.plan == "free"
      assert result.usage == %{"verifications_used" => 25, "verifications_limit" => 100}
      assert result.billing_period["start"] == "2026-02-01T00:00:00Z"
      assert result.credits["balance"] == 75
      assert result.rate_limit["requests_per_minute"] == 100
    end

    test "returns error when unauthorized" do
      expect(Req, :request, fn _opts ->
        json_response(401, %{
          "error" => %{"code" => "unauthorized", "message" => "Invalid API key"}
        })
      end)

      assert {:error, %{status: 401, body: body}} = GoodverifyEx.usage(@client)
      assert body["error"]["code"] == "unauthorized"
    end
  end

  # ── Email Verification ─────────────────────────────────────────────

  describe "verify_email/2" do
    test "verifies a deliverable email" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] == "https://api.goodverify.com/api/v1/verify/email"
        assert opts[:json] == %{email: "user@example.com"}
        assert opts[:headers] == [{"authorization", "Bearer sk_test_123"}]

        json_response(200, %{
          "email" => "user@example.com",
          "deliverability" => %{
            "status" => "deliverable",
            "reason" => "Valid mailbox"
          },
          "domain" => %{
            "name" => "example.com",
            "has_mx_records" => true,
            "has_spf" => true
          },
          "flags" => %{
            "is_catch_all" => false,
            "is_disposable" => false,
            "is_free_provider" => true,
            "is_role_account" => false
          },
          "metadata" => %{"verified_at" => "2026-02-24T12:00:00Z"}
        })
      end)

      assert {:ok, result} = GoodverifyEx.verify_email(@client, %{email: "user@example.com"})
      assert %Schemas.EmailVerifyResponse{} = result
      assert result.email == "user@example.com"
      assert %Schemas.EmailDeliverability{status: "deliverable"} = result.deliverability
      assert %Schemas.DomainInfo{name: "example.com", has_mx_records: true} = result.domain
      assert %Schemas.EmailFlags{is_disposable: false, is_free_provider: true} = result.flags
      assert %Schemas.VerificationMetadata{} = result.metadata
    end

    test "returns undeliverable email" do
      expect(Req, :request, fn _opts ->
        json_response(200, %{
          "email" => "bad@nonexistent.xyz",
          "deliverability" => %{
            "status" => "undeliverable",
            "reason" => "Mailbox does not exist"
          },
          "domain" => %{
            "name" => "nonexistent.xyz",
            "has_mx_records" => false,
            "has_spf" => false
          },
          "flags" => %{
            "is_catch_all" => false,
            "is_disposable" => false,
            "is_free_provider" => false,
            "is_role_account" => false
          },
          "metadata" => %{"verified_at" => "2026-02-24T12:00:00Z"}
        })
      end)

      assert {:ok, result} = GoodverifyEx.verify_email(@client, %{email: "bad@nonexistent.xyz"})
      assert result.deliverability.status == "undeliverable"
      assert result.domain.has_mx_records == false
    end

    test "returns validation error for invalid email" do
      expect(Req, :request, fn _opts ->
        json_response(422, %{
          "error" => %{
            "code" => "validation_error",
            "message" => "Request validation failed",
            "fields" => [
              %{"field" => "email", "message" => "is not a valid email", "code" => "format"}
            ]
          }
        })
      end)

      assert {:error, %{status: 422, body: body}} =
               GoodverifyEx.verify_email(@client, %{email: "not-an-email"})

      assert body["error"]["code"] == "validation_error"
      assert [%{"field" => "email"}] = body["error"]["fields"]
    end
  end

  # ── Phone Verification ─────────────────────────────────────────────

  describe "verify_phone/2" do
    test "verifies a valid mobile number" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] == "https://api.goodverify.com/api/v1/verify/phone"
        assert opts[:json] == %{phone_number: "+12025551234", country_code: "US"}

        json_response(200, %{
          "phone_number" => "+12025551234",
          "valid" => true,
          "phone_type" => "MOBILE",
          "carrier" => %{"name" => "Verizon", "type" => "wireless"},
          "country" => %{
            "code" => "US",
            "name" => "United States",
            "calling_code" => "+1"
          },
          "formatted" => %{
            "e164" => "+12025551234",
            "international" => "+1 202-555-1234",
            "national" => "(202) 555-1234"
          },
          "location" => %{
            "city" => "Washington",
            "state" => "DC",
            "country" => "United States"
          },
          "compliance" => %{
            "dnc" => false,
            "tcpa" => false,
            "reachable" => true,
            "tested" => true
          },
          "metadata" => %{"verified_at" => "2026-02-24T12:00:00Z"}
        })
      end)

      assert {:ok, result} =
               GoodverifyEx.verify_phone(@client, %{
                 phone_number: "+12025551234",
                 country_code: "US"
               })

      assert %Schemas.PhoneVerifyResponse{} = result
      assert result.valid == true
      assert result.phone_type == "MOBILE"
      assert %Schemas.CarrierInfo{name: "Verizon", type: "wireless"} = result.carrier
      assert %Schemas.PhoneCountry{code: "US", calling_code: "+1"} = result.country
      assert %Schemas.PhoneFormatted{e164: "+12025551234"} = result.formatted
      assert %Schemas.PhoneLocation{city: "Washington", state: "DC"} = result.location
      assert %Schemas.PhoneCompliance{dnc: false, tcpa: false, reachable: true} = result.compliance
    end

    test "verifies an invalid phone number" do
      expect(Req, :request, fn _opts ->
        json_response(200, %{
          "phone_number" => "+10000000000",
          "valid" => false,
          "phone_type" => "UNKNOWN",
          "carrier" => nil,
          "country" => nil,
          "formatted" => nil,
          "location" => nil,
          "compliance" => nil,
          "metadata" => %{"verified_at" => "2026-02-24T12:00:00Z"}
        })
      end)

      assert {:ok, result} =
               GoodverifyEx.verify_phone(@client, %{phone_number: "+10000000000"})

      assert result.valid == false
      assert result.phone_type == "UNKNOWN"
      assert result.carrier == nil
      assert result.formatted == nil
    end

    test "returns rate limit error" do
      expect(Req, :request, fn _opts ->
        json_response(429, %{
          "error" => %{
            "code" => "rate_limit_exceeded",
            "message" => "Too many requests"
          }
        })
      end)

      assert {:error, %{status: 429, body: body}} =
               GoodverifyEx.verify_phone(@client, %{phone_number: "+12025551234"})

      assert body["error"]["code"] == "rate_limit_exceeded"
    end
  end

  # ── Address Verification (single line) ─────────────────────────────

  describe "verify_address/2" do
    test "verifies a deliverable address" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] == "https://api.goodverify.com/api/v1/verify/address"
        assert opts[:json] == %{address: "123 Main St, Springfield, IL 62704", country_code: "US"}

        json_response(200, %{
          "original_address" => "123 Main St, Springfield, IL 62704",
          "deliverability" => "deliverable",
          "standardized_address" => %{
            "street" => "123 Main St",
            "city" => "Springfield",
            "state" => "IL",
            "zip" => "62704",
            "country_code" => "US",
            "formatted" => "123 Main St, Springfield, IL 62704"
          },
          "geo_location" => %{
            "latitude" => 39.7817,
            "longitude" => -89.6501,
            "accuracy" => "rooftop"
          },
          "property" => %{
            "type" => "RESIDENTIAL",
            "is_vacant" => false
          },
          "owners" => [
            %{
              "is_property_owner" => true,
              "is_deceased" => false,
              "is_litigator" => false,
              "name" => %{
                "first" => "John",
                "last" => "Smith",
                "full" => "John Smith"
              },
              "phones" => [
                %{
                  "number" => "5551234567",
                  "type" => "Mobile",
                  "carrier" => "VERIZON",
                  "rank" => 1,
                  "reachable" => true,
                  "dnc" => false,
                  "tcpa" => false,
                  "tested" => true
                }
              ],
              "emails" => [
                %{
                  "email" => "john@example.com",
                  "rank" => 1,
                  "tested" => true,
                  "type" => "personal"
                }
              ],
              "addresses" => [
                %{
                  "street" => "123 Main St",
                  "city" => "Springfield",
                  "state" => "IL",
                  "zip" => "62704",
                  "full_address" => "123 Main St, Springfield, IL 62704-1234",
                  "rank" => 1,
                  "is_mailing_address" => true
                }
              ]
            }
          ],
          "metadata" => %{"verified_at" => "2026-02-24T12:00:00Z"}
        })
      end)

      assert {:ok, result} =
               GoodverifyEx.verify_address(@client, %{
                 address: "123 Main St, Springfield, IL 62704",
                 country_code: "US"
               })

      assert %Schemas.AddressVerifyResponse{} = result
      assert result.deliverability == "deliverable"
      assert result.original_address == "123 Main St, Springfield, IL 62704"

      # Standardized address
      assert %Schemas.StandardizedAddress{} = addr = result.standardized_address
      assert addr.street == "123 Main St"
      assert addr.city == "Springfield"
      assert addr.state == "IL"
      assert addr.zip == "62704"

      # Geo location
      assert %Schemas.GeoLocation{} = geo = result.geo_location
      assert geo.latitude == 39.7817
      assert geo.longitude == -89.6501
      assert geo.accuracy == "rooftop"

      # Property
      assert %Schemas.PropertyInfo{type: "RESIDENTIAL", is_vacant: false} = result.property

      # Owners with nested person data
      assert [%Schemas.Person{} = owner] = result.owners
      assert owner.is_property_owner == true
      assert %Schemas.PersonName{first: "John", last: "Smith"} = owner.name
      assert [%Schemas.PersonPhone{number: "5551234567", carrier: "VERIZON"}] = owner.phones
      assert [%Schemas.PersonEmail{email: "john@example.com"}] = owner.emails
      assert [%Schemas.PersonAddress{city: "Springfield", is_mailing_address: true}] = owner.addresses
    end

    test "returns undeliverable address" do
      expect(Req, :request, fn _opts ->
        json_response(200, %{
          "original_address" => "999 Fake Blvd, Nowhere, ZZ 00000",
          "deliverability" => "undeliverable",
          "standardized_address" => nil,
          "geo_location" => nil,
          "property" => nil,
          "owners" => [],
          "metadata" => %{"verified_at" => "2026-02-24T12:00:00Z"}
        })
      end)

      assert {:ok, result} =
               GoodverifyEx.verify_address(@client, %{
                 address: "999 Fake Blvd, Nowhere, ZZ 00000"
               })

      assert result.deliverability == "undeliverable"
      assert result.standardized_address == nil
      assert result.geo_location == nil
      assert result.owners == []
    end

    test "returns provider unavailable error" do
      expect(Req, :request, fn _opts ->
        json_response(503, %{
          "error" => %{
            "code" => "provider_unavailable",
            "message" => "Address verification provider is currently unavailable"
          }
        })
      end)

      assert {:error, %{status: 503, body: body}} =
               GoodverifyEx.verify_address(@client, %{address: "123 Main St"})

      assert body["error"]["code"] == "provider_unavailable"
    end
  end

  # ── Address Verification (fields) ──────────────────────────────────

  describe "verify_address_fields/2" do
    test "verifies address by component fields" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] == "https://api.goodverify.com/api/v1/verify/address/fields"

        assert opts[:json] == %{
                 street: "123 Main St",
                 city: "Springfield",
                 state: "IL",
                 zip: "62704",
                 country_code: "US"
               }

        json_response(200, %{
          "original_address" => "123 Main St, Springfield, IL 62704",
          "deliverability" => "deliverable",
          "standardized_address" => %{
            "street" => "123 Main St",
            "city" => "Springfield",
            "state" => "IL",
            "zip" => "62704",
            "country_code" => "US",
            "formatted" => "123 Main St, Springfield, IL 62704"
          },
          "geo_location" => %{
            "latitude" => 39.7817,
            "longitude" => -89.6501,
            "accuracy" => "rooftop"
          },
          "property" => %{"type" => "RESIDENTIAL", "is_vacant" => false},
          "owners" => [],
          "metadata" => %{"verified_at" => "2026-02-24T12:00:00Z"}
        })
      end)

      assert {:ok, result} =
               GoodverifyEx.verify_address_fields(@client, %{
                 street: "123 Main St",
                 city: "Springfield",
                 state: "IL",
                 zip: "62704",
                 country_code: "US"
               })

      assert %Schemas.AddressVerifyResponse{} = result
      assert result.deliverability == "deliverable"
      assert result.standardized_address.city == "Springfield"
    end

    test "returns validation error for missing required fields" do
      expect(Req, :request, fn _opts ->
        json_response(422, %{
          "error" => %{
            "code" => "validation_error",
            "message" => "Request validation failed",
            "fields" => [
              %{"field" => "street", "message" => "is required", "code" => "required"},
              %{"field" => "city", "message" => "is required", "code" => "required"}
            ]
          }
        })
      end)

      assert {:error, %{status: 422, body: body}} =
               GoodverifyEx.verify_address_fields(@client, %{state: "IL", zip: "62704"})

      assert body["error"]["code"] == "validation_error"
      assert length(body["error"]["fields"]) == 2
    end
  end

  # ── Transport errors ───────────────────────────────────────────────

  describe "transport errors" do
    test "returns error on connection failure" do
      expect(Req, :request, fn _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      assert {:error, %Req.TransportError{reason: :econnrefused}} =
               GoodverifyEx.health(@client)
    end

    test "returns error on timeout" do
      expect(Req, :request, fn _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, %Req.TransportError{reason: :timeout}} =
               GoodverifyEx.verify_email(@client, %{email: "user@example.com"})
    end
  end

  # ── Client configuration ───────────────────────────────────────────

  describe "client configuration" do
    test "req_options are merged into requests" do
      client =
        GoodverifyEx.client(
          base_url: "https://api.goodverify.com",
          api_key: "sk_test_123",
          req_options: [receive_timeout: 30_000]
        )

      expect(Req, :request, fn opts ->
        assert opts[:receive_timeout] == 30_000
        json_response(200, %{"status" => "healthy", "timestamp" => "now"})
      end)

      assert {:ok, _} = GoodverifyEx.health(client)
    end
  end
end
