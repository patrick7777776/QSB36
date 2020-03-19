# QSB36

Query SunnyBoy 3.6 inverter for current output in watts, total yield and other information via the inverter's internal web interface.

Note:

* the inverter only supports http, not https
* the inverter limits the number of active sessions, so it is a good idea to log out when your program terminates 
* the inverter may close your session after a period of inactivity
* in your application, you probably want to poll the current ouput every n seconds, where n is small
* you probably want to poll the other values much less frequently
* be careful not to put too much pressure on the inverter's web server by excessive querying of historical yields
* you will have to interpret the data yourself and calculate your own deltas
* there is currently next to no input value verification; use carefully
* this module has so far only been tested on one specific actual device; there is no guarantee that this module is fit for your purpose / inverter; use at your own risk

## Example

    iex> {:ok, session} = QSB36.user_login("192.168.1.90", "password_for_user_group")
    {:ok, %QSB36.Session{host: "192.168.1.90", sid: "mOi0Eg_N4kaNhg_R"}}

    iex> QSB36.device_info(session)
    {:ok, {"SB3.6-1AV-40 231", 1234567890}}

    iex> QSB36.health_status(session)                      
    {:ok, {307, :ok}}

    iex> QSB36.current_time(session)
    {:ok, {1584382357, 0}}

    iex> QSB36.current_watts(session)
    {:ok, 262}

    iex> QSB36.total_yield(session)
    {:ok, 3388801}

    iex> QSB36.yield_daily(session, 1584309600, 1584410400) 
    {:ok, [{1584316800, 3356183}, {1584403200, 3370444}]}

    iex> QSB36.yield_5min(session, 1584316800, 1584403200)  
    {:ok,                    
      [                       
        {1584316800, 3356183},
        ...
        {1584403200, 3370444}
      ]
    }

    iex> QSB36.logout(session)
    :ok

## Installation

Add `qsb36` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:qsb36, "~> 0.1.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/qsb36](https://hexdocs.pm/qsb36).

