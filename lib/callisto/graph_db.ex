# same functionality as Repo, but customized for graph, graph repo = grepo
# if there were an ecto plugin for neo4j this would exist, but since it doesn't,
# let's just do this for now.
defmodule Callisto.GraphDB do
  alias Callisto.{Query, Vertex}

  @moduledoc """
    Defines a graph DB (repository).

    When used, the graph DB expects `:otp_app` option, which should point to
    the OTP application that has the repository configuration.  For example,

      defmodule Graph do
        use Callisto.GraphDB, otp_app: :my_app
      end

    Could be configured with:

      config :my_app, Graph,
        adapter: Callisto.Adapters.Neo4j,
        url: "http://localhost:7474",
        basic_auth: [username: "neo4j", password: "password"]

    Most of the configuration is specific to the adapter, check the adapter
    source for details.
  """

  # NOTE:  I stole a ton of this from Ecto, and probably did it wrong in the
  #        process...  ...Paul
  defmacro __using__(options) do
    quote bind_quoted: [opts: options] do
      @behaviour Callisto.GraphDB

      @otp_app Keyword.fetch!(opts, :otp_app)
      @config Application.get_env(@otp_app, __MODULE__, [])
      @adapter (opts[:adapter] || @config[:adapter])

      unless @adapter do
        raise ArgumentError, "missing :adapter configuration in config #{inspect @otp_app}, #{inspect __MODULE__}"
      end

      def query(cypher, parser \\ nil) do
        Callisto.GraphDB.Queryable.query(@adapter, cypher, parser)
      end
        
      def query!(cypher, parser \\ nil) do
        Callisto.GraphDB.Queryable.query!(@adapter, cypher, parser)
      end

      def count(matcher) do
        Callisto.GraphDB.Queryable.count(@adapter, matcher)
      end

      def exists?(matcher) do
        Callisto.GraphDB.Queryable.exists?(@adapter, matcher)
      end

      def get(finder, labels, props \\ nil) do
        Callisto.GraphDB.Queryable.get(@adapter, finder, labels, props)
      end

      def get!(finder, labels, props \\ nil) do
        Callisto.GraphDB.Queryable.get!(@adapter, finder, labels, props)
      end
    end
  end

  @doc ~S"""
    Runs an arbitrary Cypher query against Neo4j.  Can take a straight string
    or an Callisto.Query structure (if the latter, will attempt to convert
    results to structs based on the :return key -- handle_return/2).

    Optional function argument will receive the array of results (if status
    is :ok); the return from the function will replace the return.  Useful
    for dereferencing a single key to return just a list of values -- or
    for popping the first off)

      # Example:  Return only the first row's data.
      {:ok, x} = Repo.query("MATCH (x) RETURN x", fn(r) -> hd(r)["x"] end)

      # Example: Return dereferenced list.
      %Query{match: "(v:Foo)"} |> Query.returning(v: MyApp.Foo)
      |> GraphDB.query(fn(row) -> Enum.map(row, &(&1["v"])) end)
  """
  @callback query(module, String.t | struct, fun | nil) :: tuple

  @doc ~S"""
    Runs an arbitrary Cypher query against Neo4j.  Can take a straight string
    or an Callisto.Query structure.  Returns only the response.
  """
  @callback query!(String.t | struct, fun | nil) :: list(map)

  @doc ~S"""
    Returns {:ok, count} of elements that match the <matcher> with the label
    <kind>

      iex> Repo.count("(x:Disease)")
      {:ok, 0}
      iex> Repo.count("(x:Claim)")
      {:ok, 1}
  """
  @callback count(String.t | struct) :: tuple

  @doc ~S"""
    Returns true/false if there is at least one element that matches the
    parameters.

      iex> Repo.exists?("(x:Disease)")
      false
      iex> Repo.exists?("(x:Claim)")
      true
  """
  @callback exists?(String.t | struct) :: boolean

  @doc ~S"""
    Constructs query to return objects of type <type> (Vertex or Edge),
    with label(s) <labels>, and optionally properties <props>.  Returns
    tuple from query(), but on success, second element of tuple is a list
    of results cast into the appropriate structs (Vertex or Edge).
  """
  @callback get(Vertex.t | Edge.t, list(String.t | module), map | list | nil) :: tuple
  @callback get!(Vertex.t | Edge.t, list(String.t | module), map | list | nil) :: list(struct)

  # This takes a returned tuple from Neo4j and a Callisto.Query struct;
  # it looks at the Query's return key and attempts to convert the
  # returned data to the matching structs (if indicated).  If there's
  # no struct given for a key, it is unchanged.  Finally, returns
  # the tuple with the updated results.
  def handle_return(rows, %Query{return: returning}) 
       when is_list(returning) do
    Enum.map rows, fn(row) ->
      Enum.map(returning, fn({k, v}) ->
        key = to_string(k)
        cond do
          is_nil(v) -> {key, row[key]}
          v == true -> {key, Vertex.new([], row[key])}
          is_atom(v) -> {key, Vertex.new([v], row[key])}
          true -> {key, row[key]}
        end
      end)
      |> Map.new
    end
  end
  # No return structure defined, just return what we got, likely nothing.
  def handle_return(rows, %Query{return: r}) when is_nil(r), do: rows

end