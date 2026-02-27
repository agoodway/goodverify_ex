defmodule GoodverifyExTest do
  use ExUnit.Case

  alias GoodverifyEx.Client
  alias GoodverifyEx.Schemas

  describe "client/1" do
    test "creates client with defaults" do
      client = GoodverifyEx.client()
      assert %Client{base_url: "http://localhost:4000", api_key: nil} = client
    end

    test "creates client with explicit options" do
      client = GoodverifyEx.client(base_url: "https://api.example.com", api_key: "sk_test")
      assert client.base_url == "https://api.example.com"
      assert client.api_key == "sk_test"
    end
  end

  describe "schema from_map/1" do
    test "converts HealthResponse" do
      result =
        Schemas.HealthResponse.from_map(%{
          "status" => "healthy",
          "timestamp" => "2024-01-15T12:00:00Z"
        })

      assert %Schemas.HealthResponse{status: "healthy", timestamp: "2024-01-15T12:00:00Z"} =
               result
    end

    test "converts EmailVerifyResponse with nested schemas" do
      result =
        Schemas.EmailVerifyResponse.from_map(%{
          "email" => "user@example.com",
          "deliverability" => %{"status" => "deliverable", "reason" => "Valid mailbox"},
          "domain" => %{"name" => "example.com", "has_mx_records" => true, "has_spf" => true},
          "flags" => %{
            "is_catch_all" => false,
            "is_disposable" => false,
            "is_free_provider" => true,
            "is_role_account" => false
          },
          "metadata" => %{"verified_at" => "2024-01-15T12:00:00Z"}
        })

      assert %Schemas.EmailVerifyResponse{email: "user@example.com"} = result
      assert %Schemas.EmailDeliverability{status: "deliverable"} = result.deliverability
      assert %Schemas.DomainInfo{name: "example.com"} = result.domain
      assert %Schemas.EmailFlags{is_free_provider: true} = result.flags
      assert %Schemas.VerificationMetadata{} = result.metadata
    end

    test "converts PhoneVerifyResponse with nested schemas" do
      result =
        Schemas.PhoneVerifyResponse.from_map(%{
          "phone_number" => "+12025551234",
          "valid" => true,
          "phone_type" => "MOBILE",
          "carrier" => %{"name" => "Verizon", "type" => "wireless"},
          "country" => %{"code" => "US", "name" => "United States", "calling_code" => "+1"},
          "formatted" => %{
            "e164" => "+12025551234",
            "international" => "+1 202-555-1234",
            "national" => "(202) 555-1234"
          },
          "location" => %{"city" => "Washington", "state" => "DC", "country" => "United States"},
          "metadata" => %{"verified_at" => "2024-01-15T12:00:00Z"}
        })

      assert %Schemas.PhoneVerifyResponse{valid: true, phone_type: "MOBILE"} = result
      assert %Schemas.CarrierInfo{name: "Verizon"} = result.carrier
      assert %Schemas.PhoneCountry{code: "US"} = result.country
      assert %Schemas.PhoneFormatted{e164: "+12025551234"} = result.formatted
      assert %Schemas.PhoneLocation{city: "Washington"} = result.location
    end

    test "converts AddressVerifyResponse with array of Person" do
      result =
        Schemas.AddressVerifyResponse.from_map(%{
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
          "owners" => [
            %{
              "is_property_owner" => true,
              "name" => %{"first" => "John", "last" => "Smith", "full" => "John Smith"},
              "phones" => [%{"number" => "5551234567", "type" => "Mobile", "rank" => 1}],
              "emails" => [%{"email" => "john@example.com", "rank" => 1}],
              "addresses" => []
            }
          ],
          "metadata" => %{"verified_at" => "2024-01-15T12:00:00Z"}
        })

      assert %Schemas.AddressVerifyResponse{deliverability: "deliverable"} = result
      assert %Schemas.StandardizedAddress{city: "Springfield"} = result.standardized_address
      assert %Schemas.GeoLocation{latitude: 39.7817} = result.geo_location
      assert %Schemas.PropertyInfo{type: "RESIDENTIAL"} = result.property

      assert [%Schemas.Person{is_property_owner: true} = person] = result.owners
      assert %Schemas.PersonName{first: "John"} = person.name
      assert [%Schemas.PersonPhone{number: "5551234567"}] = person.phones
      assert [%Schemas.PersonEmail{email: "john@example.com"}] = person.emails
    end

    test "handles nil values" do
      assert nil == Schemas.GeoLocation.from_map(nil)
    end

    test "ignores unknown fields" do
      result =
        Schemas.HealthResponse.from_map(%{
          "status" => "healthy",
          "timestamp" => "now",
          "unknown_field" => "ignored"
        })

      assert result.status == "healthy"
    end

    test "converts ErrorResponse with nested ErrorDetail" do
      result =
        Schemas.ErrorResponse.from_map(%{
          "error" => %{
            "code" => "validation_error",
            "message" => "Request validation failed",
            "fields" => [
              %{"field" => "email", "message" => "is required", "code" => "required"}
            ]
          }
        })

      assert %Schemas.ErrorResponse{error: error} = result
      assert %Schemas.ErrorDetail{code: "validation_error"} = error
      assert [%Schemas.ErrorFieldDetail{field: "email"}] = error.fields
    end
  end

  describe "generated API functions" do
    test "all expected functions are generated" do
      Code.ensure_loaded!(GoodverifyEx)
      assert function_exported?(GoodverifyEx, :health, 1)
      assert function_exported?(GoodverifyEx, :usage, 1)
      assert function_exported?(GoodverifyEx, :verify_email, 2)
      assert function_exported?(GoodverifyEx, :verify_phone, 2)
      assert function_exported?(GoodverifyEx, :verify_address, 2)
      assert function_exported?(GoodverifyEx, :verify_address_fields, 2)
    end
  end
end
