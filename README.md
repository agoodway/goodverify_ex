# GoodverifyEx

Elixir client for the [GoodVerify](https://goodverify.com) API. Verify emails, phone numbers, and addresses with typed responses generated from the OpenAPI spec.

## Installation

Add `goodverify_ex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:goodverify_ex, "~> 0.1.0"}
  ]
end
```

Install directly from GitHub:

```elixir
def deps do
  [
    {:goodverify_ex, git: "https://github.com/agoodway/goodverify_ex.git"}
  ]
end
```

## Configuration

### Application config

```elixir
# config/config.exs
config :goodverify_ex,
  base_url: "https://goodverify.dev",
  api_key: "sk_live_..."
```

### Runtime / per-request

```elixir
client = GoodverifyEx.client(
  base_url: "https://goodverify.dev",
  api_key: "sk_live_..."
)
```

You can also pass `req_options` to customize the underlying [Req](https://hexdocs.pm/req) HTTP client:

```elixir
client = GoodverifyEx.client(
  api_key: "sk_live_...",
  req_options: [receive_timeout: 30_000]
)
```

## Usage

Every function takes a `%GoodverifyEx.Client{}` as the first argument and returns `{:ok, struct}` or `{:error, reason}`.

### Email verification

```elixir
client = GoodverifyEx.client(api_key: "sk_live_...")

{:ok, result} = GoodverifyEx.verify_email(client, %{email: "user@example.com"})

result.email                       #=> "user@example.com"
result.deliverability.status       #=> "deliverable" | "undeliverable" | "risky"
result.deliverability.reason       #=> "Valid mailbox"
result.domain.name                 #=> "example.com"
result.domain.has_mx_records       #=> true
result.domain.has_spf              #=> true
result.flags.is_disposable         #=> false
result.flags.is_free_provider      #=> true
result.flags.is_catch_all          #=> false
result.flags.is_role_account       #=> false
result.metadata.verified_at        #=> "2026-02-24T12:00:00Z"
```

### Phone verification

```elixir
{:ok, result} = GoodverifyEx.verify_phone(client, %{
  phone_number: "+12025551234",
  country_code: "US"
})

result.valid                       #=> true
result.phone_type                  #=> "MOBILE" | "LANDLINE" | "VOIP" | "UNKNOWN"
result.carrier.name                #=> "Verizon"
result.carrier.type                #=> "wireless"
result.country.code                #=> "US"
result.country.calling_code        #=> "+1"
result.formatted.e164              #=> "+12025551234"
result.formatted.international     #=> "+1 202-555-1234"
result.formatted.national          #=> "(202) 555-1234"
result.location.city               #=> "Washington"
result.location.state              #=> "DC"
result.compliance.dnc              #=> false
result.compliance.tcpa             #=> false
result.compliance.reachable        #=> true
```

### Address verification (single line)

```elixir
{:ok, result} = GoodverifyEx.verify_address(client, %{
  address: "123 Main St, Springfield, IL 62704",
  country_code: "US"
})

result.deliverability              #=> "deliverable" | "undeliverable"
result.original_address            #=> "123 Main St, Springfield, IL 62704"

# Standardized address
result.standardized_address.street       #=> "123 Main St"
result.standardized_address.city         #=> "Springfield"
result.standardized_address.state        #=> "IL"
result.standardized_address.zip          #=> "62704"
result.standardized_address.country_code #=> "US"
result.standardized_address.formatted    #=> "123 Main St, Springfield, IL 62704"

# Geolocation
result.geo_location.latitude       #=> 39.7817
result.geo_location.longitude      #=> -89.6501
result.geo_location.accuracy       #=> "rooftop"

# Property info
result.property.type               #=> "RESIDENTIAL" | "COMMERCIAL"
result.property.is_vacant          #=> false

# Owner data (list of Person structs)
[owner | _] = result.owners
owner.name.first                   #=> "John"
owner.name.last                    #=> "Smith"
owner.is_property_owner            #=> true

# Owner phones, emails, and addresses
[phone | _] = owner.phones
phone.number                       #=> "5551234567"
phone.type                         #=> "Mobile"
phone.carrier                      #=> "VERIZON"
phone.reachable                    #=> true
phone.dnc                          #=> false

[email | _] = owner.emails
email.email                        #=> "john@example.com"
email.type                         #=> "personal"

[addr | _] = owner.addresses
addr.full_address                  #=> "123 Main St, Springfield, IL 62704-1234"
addr.is_mailing_address            #=> true
```

### Address verification (by fields)

```elixir
{:ok, result} = GoodverifyEx.verify_address_fields(client, %{
  street: "123 Main St",
  city: "Springfield",
  state: "IL",
  zip: "62704",
  country_code: "US"
})

# Returns the same AddressVerifyResponse as verify_address/2
result.deliverability              #=> "deliverable"
```

### Health check

```elixir
{:ok, health} = GoodverifyEx.health(client)
health.status                      #=> "healthy"
health.timestamp                   #=> "2026-02-11T12:00:00Z"
```

### Usage stats

```elixir
{:ok, usage} = GoodverifyEx.usage(client)
usage.plan                         #=> "free"
usage.billing_period               #=> %{"start" => "...", "end" => "..."}
usage.credits                      #=> %{"balance" => 75, "used_this_period" => 25}
usage.rate_limit                   #=> %{"requests_per_minute" => 100}
```

## Error handling

API errors return `{:error, %{status: integer, body: map}}`:

```elixir
case GoodverifyEx.verify_email(client, %{email: "bad"}) do
  {:ok, result} ->
    # handle success

  {:error, %{status: 422, body: body}} ->
    # validation error
    body["error"]["code"]     #=> "validation_error"
    body["error"]["message"]  #=> "Request validation failed"
    body["error"]["fields"]   #=> [%{"field" => "email", ...}]

  {:error, %{status: 401}} ->
    # invalid API key

  {:error, %{status: 429}} ->
    # rate limited

  {:error, %Req.TransportError{reason: reason}} ->
    # connection error (:econnrefused, :timeout, etc.)
end
```

## Response types

All responses are typed structs under `GoodverifyEx.Schemas`. Schemas are generated at compile time from `openapi.json` and recompile automatically when the spec changes.

| Function                | Response struct                                  |
|------------------------|--------------------------------------------------|
| `health/1`             | `Schemas.HealthResponse`                         |
| `usage/1`              | `Schemas.UsageResponse`                          |
| `verify_email/2`       | `Schemas.EmailVerifyResponse`                    |
| `verify_phone/2`       | `Schemas.PhoneVerifyResponse`                    |
| `verify_address/2`     | `Schemas.AddressVerifyResponse`                  |
| `verify_address_fields/2` | `Schemas.AddressVerifyResponse`               |

## Testing

The test suite uses [Mimic](https://hex.pm/packages/mimic) to mock `Req` HTTP calls:

```sh
mix test
```

## License

See [LICENSE](LICENSE) for details.
