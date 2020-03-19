defmodule QSB36 do
  @moduledoc """
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
  """

  @content_type_json [{"Content-Type", "application/json"}]
  @device_name "6800_10821E00"
  @serial_number "6800_00A21E00"
  @health_status "6180_08214800"
  @health_dict %{
    35 => :alm,
    303 => :off,
    307 => :ok,
    455 => :wrn,
    1719 => :com_nok,
    1725 => :not_conn,
    2130 => :conn_sett,
    3325 => :conn_fail,
    3426 => :wps_is_act
  }
  @current_w "6100_40263F00"
  @total_yield_w "6400_00260100"
  @interval_day 28704
  @interval_5min 28672

  defmodule Session do
    @moduledoc """
    Holds `host` and, once logged in, `sid`.
    """
    defstruct host: nil, sid: nil
    def new(host), do: %Session{host: host, sid: nil}
    def new(host, sid), do: %Session{host: host, sid: sid}
    def set_sid(%Session{} = session, sid), do: %Session{session | sid: sid}
  end

  alias QSB36.Session

  @doc """
  Log in on `host` with password `pass`; the user group is "user" (as opposed to "installer").
  Returns `{:ok, session}` or `{:error, reason}`.
  """
  def user_login(host, pass) do
    session = Session.new(host)

    case post_json(session, "/dyn/login.json", %{right: "usr", pass: pass}) do
      {:ok, %{"result" => %{"sid" => nil}}} ->
        {:error, "Incorrect password."}

      {:ok, %{"result" => %{"sid" => sid}}} ->
        {:ok, Session.set_sid(session, sid)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Asks the inverter for its current time (unix seconds) and offset (hours).
  Returns `{:ok, {time, offset}}` or `{:error, reason}`.
  
  ## Example

      iex> {:ok, {time, offset}} = QSB36.current_time(session)
      {:ok, {1584382357, 0}}
  """
  def current_time(%Session{} = session) do
    case post_json(session, "/dyn/getTime.json", %{"destDev" => []}) do
      {:ok, result} ->
        case skip_intermediate(result) do
          {:ok, %{"tm" => time, "ofs" => offset}} -> {:ok, {time, offset}}
          {:error, error} -> {:error, error}
          other -> {:error, other}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Asks the inverter for its device name and serial number.
  Returns `{:ok, {device_name, serial_number}}` or `{:error, reason}`.
  
  ## Example

      iex> QSB36.device_info(session)
      {:ok, {"SB3.6-1AV-40 231", 1234567890}}
  """
  def device_info(%Session{} = session) do
    with {:ok, result} <- get_values(session, [@device_name, @serial_number]),
         {:ok, device_name} <- extract_first_value(result, @device_name),
         {:ok, serial_number} <- extract_first_value(result, @serial_number) do
      {:ok, {device_name, serial_number}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Asks the inverter for its operational health status.
  Returns `{:ok, {tag, description}}` or `{:error, reason}`.

  Descriptive atoms are known for the following tags:  
  * 35 => :alm
  * 303 => :off
  * 307 => :ok
  * 455 => :wrn
  * 1719 => :com_nok
  * 1725 => :not_conn
  * 2130 => :conn_sett
  * 3325 => :conn_fail
  * 3426 => :wps_is_act
  
  ## Example

      iex> QSB36.health_status(session)                      
      {:ok, {307, :ok}}
  """
  def health_status(%Session{} = session) do
    with {:ok, result} <- get_values(session, @health_status),
         {:ok, [%{"tag" => tag}]} <- extract_first_value(result, @health_status),
         description <- Map.get(@health_dict, tag) do
      {:ok, {tag, description}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Asks the inverter for the current output in watts. Returns `{:ok, watts}` or `{:error, reason}`.

  ## Example

      iex> QSB36.current_watts(session)
      {:ok, 262} # another rainy day
  
  """
  def current_watts(%Session{} = session) do
    with {:ok, result} <- get_values(session, [@current_w]),
         {:ok, watts} <- extract_first_value(result, @current_w) do
      case watts do
        nil -> {:ok, 0}
        _ -> {:ok, watts}
      end
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Asks the inverter for its total yield in watts to date. Returns `{:ok, watts}` or `{:error, reason}`.

  ## Example

      iex> QSB36.total_yield(session)
      {:ok, 3388801}
  """
  def total_yield(%Session{} = session) do
    with {:ok, result} <- get_values(session, [@total_yield_w]),
         {:ok, watts} <- extract_first_value(result, @total_yield_w) do
      {:ok, watts}
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Asks the inverter for the daily yield in watts between `start_time` and `end_time`, which are
  given in unix seconds. The inverter returns a list of `{time_stamp, total_yield_in_watts}`-tuples 
  that fall between `start_time` and `end_time`. Returns `{:ok, [{time_stamp, watts}, ...]}` or `{:error, reason}`.

  ## Example
 
      iex> QSB36.yield_daily(session, 1584309600, 1584410400) 
      {:ok, [{1584316800, 3356183}, {1584403200, 3370444}]}
 
      iex> mar16watts = 3370444 - 3356183
      14261
	"""
  def yield_daily(%Session{} = session, start_time, end_time),
    do: yield(session, @interval_day, start_time, end_time)

  @doc """
  Asks the inverter for the 5-minute yield intervals in watts between `start_time` and `end_time`, which are
  given in unix seconds. The inverter returns a list of `{time_stamp, total_yield_in_watts}`-tuples 
  that fall between `start_time` and `end_time`. Returns `{:ok, [{time_stamp, watts}, ...]}` or `{:error, reason}`.

  ## Example

      iex> {:ok, series} = QSB36.yield_5min(session, 1584316800, 1584403200)  
      {:ok,                    
        [                       
          {1584316800, 3356183},
          {1584317100, 3356183},
          {1584317400, 3356183},
          ...
          {1584345600, 3356316},
          {1584345900, 3356330},
          {1584346200, 3356345},
          {1584346500, 3356361},
          {1584346800, 3356382},
          ...
          {1584402600, 3370444}, 
          {1584402900, 3370444}, 
          {1584403200, 3370444}
        ]
      }
	"""
  def yield_5min(%Session{} = session, start_time, end_time),
    do: yield(session, @interval_5min, start_time, end_time)

  defp yield(session, key, start_time, end_time)
       when is_integer(start_time) and is_integer(end_time) and start_time <= end_time and
              start_time >= 0 do
    with {:ok, result} <-
           post_json(session, "/dyn/getLogger.json", %{
             "destDev" => [],
             "key" => key,
             "tStart" => start_time,
             "tEnd" => end_time
           }),
         {:ok, series} <- skip_intermediate(result),
         tuple_series <- convert(series) do
      {:ok, tuple_series}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp convert(series) do
    series
    |> Enum.map(fn %{"t" => t, "v" => v} -> {t, v} end)
  end

  defp skip_intermediate(%{"result" => map}) do
    intermediate_key =
      map
      |> Map.keys()
      |> Enum.take(1)
      |> hd

    inner =
      map
      |> Map.get(intermediate_key, %{})

    {:ok, inner}
  end

  defp skip_intermediate(other), do: {:error, other}

  defp extract_first_value(%{"result" => _map} = m, key) do
    case skip_intermediate(m) do
      {:ok, inner} ->
        case Map.get(inner, key) do
          %{"1" => [%{"val" => value}]} -> {:ok, value}
          other -> {:error, {:not_found, key, other}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp extract_first_value(other, key), do: {:error, {:not_found, key, other}}

  defp get_values(session, keys) when is_list(keys),
    do: post_json(session, "/dyn/getValues.json", %{"destDev" => [], "keys" => keys})

  defp get_values(session, tag), do: get_values(session, [tag])

  @doc """
  Closes the `session`. Returns `:ok` or `{:error, reason}`.


  ## Example

      iex> QSB36.logout(session)
      :ok
  """
  def logout(%Session{} = session) do
    case post_json(session, "/dyn/logout.json", %{}) do
      {:ok, %{"result" => %{"isLogin" => false}}} -> :ok
      error -> error
    end
  end

  defp post_json(%Session{} = session, file, body) do
    url =
      case session.sid do
        nil -> ~s"http://#{session.host}#{file}"
        sid -> ~s"http://#{session.host}#{file}?sid=#{sid}"
      end

    with {:ok, request_body} <- Jason.encode(body),
         {:ok, %HTTPoison.Response{body: response_body}} <-
           HTTPoison.post(url, request_body, @content_type_json),
         {:ok, map} <- Jason.decode(response_body) do
      {:ok, map}
    else
      {:error, error} -> {:error, error}
    end
  end
end
