export stationary_polynomial, stationary_mean, 
       stationary_variance, stationary_covariance_ellipsoid, 
       max_entropy_measure, approximate_stationary_measure,
       stationary_probability_mass

"""
	stationary_pop(MP::MarkovProcess, v::APL, d::Int, solver)

returns SOS program of degree `d` for compuitation of a **lower** bound
on the expecation of a polynomial observable ``v(x)`` at steady state of the
Markov process `MP`.
"""
function stationary_pop(MP::MarkovProcess, p::APL, order::Int, solver,
                        P::Partition = trivial_partition(MP.X);
                        inner_approx = SOSCone)
    model = SOSModel(solver)
    PolyJuMP.setdefault!(model, PolyJuMP.NonNegPoly, inner_approx)
    @variable(model, s)
    w = Dict(v => (props(P.graph, v)[:cell] isa Singleton ?
                   @variable(model) :
                   @variable(model, [1:1], Poly(monomials(MP.x, 0:order)))[1]) for v in vertices(P.graph))

    for v in vertices(P.graph)
        add_stationarity_constraints!(model, MP, v, P, props(P.graph, v)[:cell], w, s-p)
    end

    for e in edges(P.graph)
        add_coupling_constraints!(model, MP, e, P, w)
    end
    @objective(model, Max, s)
    return model, w
end

"""
	stationary_polynomial(MP::MarkovProcess, v::APL, d::Int, solver)

returns a **lower** bound on the expecation of a polynomial observables ``v(x)``
at steady state of the Markov process `MP`. The bound is computed based on an
SOS program over a polynomial of degree at most `d`; the bounds can be
tightened by increasing `d`. The program is solved with `solver`.
"""
function stationary_polynomial(MP::MarkovProcess, v::APL, d::Int, solver, 
                               P::Partition = trivial_partition(MP.X);
                               inner_approx = SOSCone)
    model, w = stationary_pop(MP, v, d, solver, P, inner_approx=inner_approx)
    optimize!(model)
    return Bound(objective_value(model), model, P, Dict(key => value(w[key]) for key in keys(w)))
end

stationary_polynomial(RP::ReactionProcess, v::Num, d::Int, solver, P::Partition = trivial_partition(RP.JumpProcess.X)) = stationary_polynomial(RP.JumpProcess, polynomialize_expr(v, RP.species_to_state), d, solver, P)
stationary_polynomial(LP::LangevinProcess, v::Num, d::Int, solver, P::Partition = trivial_partition(LP.DiffusionProcess.X)) = stationary_polynomial(LP.DiffusionProcess, polynomialize_expr(v, LP.species_to_state), d, solver, P)
stationary_polynomial(MP::MarkovProcess, v::Num, d::Int, solver, P::Partition = trivial_partition(MP.X)) = stationary_polynomial(MP, polynomialize_expr(v, MP.poly_vars), d, solver, P)

"""
	stationary_mean(MP::MarkovProcess, v::APL, d::Int, solver)

returns **lower** and **upper** bound on the observable ``v(x)`` at steady state of
the Markov process `MP`. Bounds are computed based on SOS programs over a
polynomial of degree at most `d`; the bounds can be tightened by increasing
`d`. The program is solved with `solver`.
"""
function stationary_mean(MP::MarkovProcess, v::APL, d::Int, solver,
                         P::Partition = trivial_partition(MP.X);
                         inner_approx = SOSCone)
    lb = stationary_polynomial(MP, v, d, solver, P, inner_approx=inner_approx)
    ub = stationary_polynomial(MP, -v, d, solver, P, inner_approx=inner_approx)
	ub.value *= -1
    return lb, ub
end

stationary_mean(RP::ReactionProcess, S, d::Int, solver, 
                P::Partition = trivial_partition(RP.JumpProcess.X);
                inner_approx = SOSCone) = stationary_mean(RP.JumpProcess, RP.species_to_state[S], d, solver, P, inner_approx=inner_approx)
stationary_mean(LP::LangevinProcess, S, d::Int, solver, 
                P::Partition = trivial_partition(LP.DiffusionProcess.X);
                inner_approx = SOSCone) = stationary_mean(LP.DiffusionProcess, LP.species_to_state[S], d, solver, P, inner_approx=inner_approx)
stationary_mean(MP::MarkovProcess, v::Num, d::Int, solver, 
                P::Partition = trivial_partition(MP.X);
                inner_approx = SOSCone) = stationary_mean(MP, polynomialize_expr(v, MP.poly_vars), d, solver, P, inner_approx=inner_approx)

"""
	stationary_mean(rn::ReactionSystem, S0::Dict, S, d::Int, solver,
			scales = Dict(s => 1 for s in species(rn));
			auto_scaling = false)

returns **lower** and **upper** bound on the mean of species `S` of the reaction
network `rn` with initial condition `S0` (for all species!). The bound is based
on an SOS program of order `d` solved via `solver`; the bounds can be tightened
by increasing `d`.

For numerical stability, it is recommended to provide scales of the expected
magnitude of molecular counts for the different species at steady state.
If the system is **closed** it is also possible to enable auto_scaling which will
find the maximum molecular counts for each species under stoichiometry
constraints (via LP).

If the initial condition of the reaction network under investigation is
unknown or irrelevant, simply call

	stationary_mean(rn::ReactionSystem, S, d::Int, solver,
			scales = Dict(s => 1 for s in species(rn))).
"""
function stationary_mean(rn::ReactionSystem, S0::Dict, S, d::Int, solver,
	 					 scales = Dict(s => 1 for s in species(rn));
						 params::Dict = Dict(), auto_scaling = false, inner_approx = SOSCone)
	RP, S0 = reaction_process_setup(rn, S0, scales = scales, auto_scaling = auto_scaling, solver = solver, params = params)
 	return stationary_mean(RP.JumpProcess, RP.species_to_state[S], d, solver, inner_approx=inner_approx)
end

function stationary_mean(rn::ReactionSystem, S, d::Int, solver,
					     scales = Dict(s => 1 for s in species(rn));
						 params::Dict = Dict(), inner_approx = SOSCone)
	RP = reaction_process_setup(rn, scales = scales, params = params)
	return stationary_mean(RP.JumpProcess, RP.species_to_state[S], d, solver, inner_approx=inner_approx)
end


"""
	stationary_variance(MP::MarkovProcess, v::APL, d::Int, solver)

returns SOS program of degree `d` for computation of an **upper** bound on the
variance of a polynomial observables `v` at steady state of the Markov process
`MP`.
"""
function stationary_variance(MP::MarkovProcess, p::APL, d::Int, solver, 
                             P::Partition = trivial_partition(MP.X);
                             inner_approx = SOSCone)
    model = SOSModel(solver)
    PolyJuMP.setdefault!(model, PolyJuMP.NonNegPoly, inner_approx)
	w = Dict(v => (props(P.graph, v)[:cell] isa Singleton ?
                   @variable(model) :
                   @variable(model, [1:1], Poly(monomials(MP.x, 0:d)))[1]) for v in vertices(P.graph))
    @variable(model, s)
    @variable(model, S[1:2])
    @constraint(model, [1 S[1]; S[1] S[2]] in PSDCone())

	for v in vertices(P.graph)
        add_stationarity_constraints!(model, MP, v, P, props(P.graph, v)[:cell], w, s + p^2 + 2*S[1]*p)
    end

	for e in edges(P.graph)
        add_coupling_constraints!(model, MP, e, P, w)
    end

    @objective(model, Max, s-S[2])
    optimize!(model)
    return Bound(-objective_value(model), model, P, Dict(key => value(w[key]) for key in keys(w)))
end

stationary_variance(RP::ReactionProcess, v, d::Int, solver, 
                    P::Partition = trivial_partition(RP.JumpProcess.X);
                    inner_approx = SOSCone) = stationary_variance(RP.JumpProcess, polynomialize_expr(v, RP.species_to_state), d, solver, P, inner_approx=inner_approx)
stationary_variance(LP::LangevinProcess, v, d::Int, solver, 
                    P::Partition = trivial_partition(LP.DiffusionProcess.X);
                    inner_approx = SOSCone) = stationary_variance(LP.DiffusionProcess, polynomialize_expr(v, LP.species_to_state), d, solver, P, inner_approx=inner_approx)
stationary_variance(MP::MarkovProcess, v::Num, d::Int, solver, 
                    P::Partition = trivial_partition(MP.X);
                    inner_approx = SOSCone) = stationary_variance(MP, polynomialize_expr(v, MP.poly_vars), d, solver, P, inner_approx=inner_approx)

"""
	stationary_variance(rn::ReactionSystem, S0, x, d::Int, solver,
			    scales = Dict(s => 1 for s in species(rn));
			    auto_scaling = false)

returns **upper** bound on the variance of species `S` of the reaction
network rn with initial condition `S0` (for all species!). The bound is based
on an SOS program of degree `d` solved via `solver`; the bound can be tightened
by increasing `d`.

For numerical stability, it is recommended to provide scales of the expected
magnitude of molecular counts for the different species at steady state. If
the system is **closed** it is also possible to enable `auto_scaling` which will
find the maximum molecular counts for each species under stoichiometry
constraints (via LP).

If the initial condition of the reaction network under investigation is
unknown or irrelevant, simply call

	stationary_variance(rn::ReactionSystem, S, d::Int, solver,
			    scales = Dict(s => 1 for s in species(rn)))
"""
function stationary_variance(rn::ReactionSystem, S0, S, d::Int, solver,
	 						 scales = Dict(s => 1 for s in species(rn));
							 auto_scaling = false, params::Dict = Dict(),
                             inner_approx = SOSCone)
	RP, S0 = reaction_process_setup(rn, S0, scales = scales, auto_scaling = auto_scaling, solver = solver, params = params)
 	return stationary_variance(RP.JumpProcess, RP.species_to_state[S], d, solver, inner_approx=inner_approx)
end

function stationary_variance(rn::ReactionSystem, S, d::Int, solver,
							 scales = Dict(s => 1 for s in species(rn));
							 params::Dict = Dict(), inner_approx = SOSCone)
	RP = reaction_process_setup(rn, scales = scales, params = params)
	return stationary_variance(RP.JumpProcess, RP.species_to_state[S], d, solver, inner_approx=inner_approx)
end

@doc raw"""
	stationary_covariance_ellipsoid(MP::MarkovProcess, v::Vector{<:APL}, d::Int, solver)

returns an **upper** on the volume of the covariance ellipsoid of a vector of
polynomial observables ``v(x)``, i.e., ``\text{det}(\mathbb{E} [v(x)v(x)^\top] - \mathbb{E}[v(x)] \mathbb{E}[v(x)]^\top)``, at steady state of the
Markov process `MP`.
The bounds are computed via an SOS program of degree `d`, hence can be tightened
by increasing `d`. This computation requires a `solver` that can handle
exponential cone constraints.
"""
function stationary_covariance_ellipsoid(MP::MarkovProcess, v::Vector{<:APL}, d::Int, solver, 
                                         P::Partition = trivial_partition(MP.X);
                                         inner_approx = SOSCone)
    n = length(v)
    model = SOSModel(solver)
    PolyJuMP.setdefault!(model, PolyJuMP.NonNegPoly, inner_approx)
	w = Dict(v => (props(P.graph, v)[:cell] isa Singleton ?
                   @variable(model) :
                   @variable(model, [1:1], Poly(monomials(MP.x, 0:d)))[1]) for v in vertices(P.graph))
    @variable(model, s)
    @variable(model, S[1:n+1, 1:n+1], PSD)
    @variable(model, U[1:2*n, 1:2*n], PSD)
    @variable(model, r[1:n])
    @variable(model, q[1:n])

	@constraint(model, S[1:n,1:n] .== U[1:n, 1:n])
    @constraint(model, [i in 1:n, j in 1:i], -2*U[n+i,j] - (i == j ? U[n+i,n+i] - r[i] : 0) == 0)
    @constraint(model, [i in 1:n], [-1, q[i], r[i]] in MOI.DualExponentialCone())

	for vertex in vertices(P.graph)
        add_stationarity_constraints!(model, MP, vertex, P, props(P.graph, vertex)[:cell], w, s + (v'*S[1:n, 1:n]*v + 2*S[end,1:n]'*v))
    end

	for e in edges(P.graph)
        add_coupling_constraints!(model, MP, e, P, w)
    end

    @objective(model, Max, s-S[n+1,n+1]-sum(q))
    optimize!(model)
    return Bound(exp(-objective_value(model)), model, P, Dict(key => value(w[key]) for key in keys(w)))
end

stationary_covariance_ellipsoid(RP::ReactionProcess, v::Vector, d::Int, solver, 
                                P::Partition = trivial_partition(RP.JumpProcess.X);
                                inner_approx = SOSCone) = stationary_variance(RP.JumpProcess, [RP.species_to_state[x] for x in v], d, solver, P, inner_approx=inner_approx)
stationary_covariance_ellipsoid(MP::MarkovProcess, v::Vector{Num}, d::Int, solver, 
                                P::Partition = trivial_partition(MP.X);
                                inner_approx = SOSCone) = stationary_variance(MP, polynomialize_expr(v, MP.poly_vars), d, solver, P, inner_approx=inner_approx)

@doc raw"""
	stationary_covariance_ellipsoid(rn::ReactionSystem, S0::Dict, S::AbstractVector, d::Int, solver,
					scales = Dict(s => 1 for s in species(rn));
					auto_scaling = false)

returns an **upper** on the volume of the covariance ellipsoid of any subset `S`
of the chemical species in the reaction network `rn`, i.e., ``\text{det}(\mathbb{E}[SS^\top] - \mathbb{E}[S] \mathbb{E}[S]^\top)``,
at steady state of the associated jump process. The reaction network is assumed
to have the deterministic initial state `S0` (all species must be included here!).
The bounds are computed via an SOS program of degree `d`, hence can be tightened
by increasing `d`. This computation requires a solver that can deal with
exponential cone constraints.

For numerical stability, it is recommended to provide scales of the expected
magnitude of molecular counts for the different species at steady state. If
the system is **closed** it is also possible to enable auto_scaling which will
find the maximum molecular counts for each species under stoichiometry
constraints (via LP).

If the initial condition of the reaction network under investigation is
unknown or irrelevant, simply call

	stationary_covariance_ellipsoid(rn::ReactionSystem, S, d::Int, solver,
					scales = Dict(s => 1 for s in species(rn)))
"""
function stationary_covariance_ellipsoid(rn::ReactionSystem, S0::Dict, S::AbstractVector, d::Int, solver,
	 									 scales = Dict(s => 1 for s in species(rn));
										 auto_scaling = false, params::Dict = Dict(),
                                         inner_approx = SOSCone)
	RP, x0 = reaction_process_setup(rn, S0, scales = scales, auto_scaling = auto_scaling, solver = solver, params = params)
 	return stationary_covariance_ellipsoid(RP.JumpProcess, [RP.species_to_state[x] for x in S], d, solver, inner_approx=inner_approx)
end

function stationary_covariance_ellipsoid(rn::ReactionSystem, S::Vector, d::Int, solver,
	 									 scales = Dict(s => 1 for s in species(rn));
										 params::Dict = Dict(), inner_approx = SOSCone)
	RP = reaction_process_setup(rn, scales = scales, params = params)
	return stationary_covariance_ellipsoid(RP.JumpProcess, [RP.species_to_state[x] for x in S], d, solver, inner_approx=inner_approx)
end

"""
	stationary_probability_mass(MP::MarkovProcess, X::BasicSemialgebraicSet, d::Int,
							solver)

returns **lower** and **upper** bounds on the probability mass associated with the set `X`.
`d` refers to the order of the relaxation used, again the bounds will tighten
monotonically with increasing order. solver refers to the optimizer used to solve
the semidefinite programs which optimal values furnish the bounds. This is the
weakest formulation that can be used to compute bounds on the probabiltiy mass
associated with a Basic semialgebraic set. For sensible results the set `X` should have non-
empty interior. In order to improve the bounds the user should supply a carefully defined 
partition of the state space. In that case it is most sensible to choose `X` as a subset of the element 
of said partition. Then, one should call

    stationary_probability_mass(MP::MarkovProcess, v::Int, order::Int, solver,
                                 P::Partition)
where `v` refers to the vertex of the partition graph that corresponds to the set `X`. 
"""
function stationary_probability_mass(MP::MarkovProcess, X::BasicSemialgebraicSet, d::Int, solver;
                                     inner_approx = SOSCone)
	P = split_state_space(MP, X)
 	return stationary_probability_mass(MP, [1], d, solver, P, inner_approx=inner_approx)
end

function stationary_probability_mass(MP::MarkovProcess, v::Int, order::Int, solver, P::Partition;
                                     inner_approx = SOSCone)
	return stationary_probability_mass(MP, [v], order, solver, P, inner_approx=inner_approx)
end

function stationary_probability_mass(MP::MarkovProcess, v::AbstractVector{Int}, order::Int, solver, P::Partition;
                                     inner_approx = SOSCone)
	model, w = stationary_indicator(MP, v, order, P, solver; sense = 1, inner_approx = inner_approx) # Max
	optimize!(model)
	ub = Bound(-objective_value(model), model, P, Dict(v => value(w[v]) for v in vertices(P.graph)))
	model, w = stationary_indicator(MP, v, order, P, solver; sense = -1, inner_approx = inner_approx) # Min
	optimize!(model)
	lb = Bound(objective_value(model), model, P, Dict(v => value(w[v]) for v in vertices(P.graph)))
 	return lb, ub
end

function stationary_indicator(MP::MarkovProcess, v_target::Int, order::Int, P::Partition, solver;
                              sense = 1, inner_approx = SOSCone)
    return stationary_indicator(MP, [v_target], order, P, solver, sense = sense, inner_approx=inner_approx)
end

function stationary_indicator(MP::MarkovProcess, v_target::AbstractVector{Int}, order::Int, P::Partition, solver; 
                              sense = 1, inner_approx = SOSCone)
    model = SOSModel(solver)
    PolyJuMP.setdefault!(model, PolyJuMP.NonNegPoly, inner_approx)
    @variable(model, s)
    w = Dict(v => (props(P.graph, v)[:cell] isa Singleton ?
                   @variable(model) :
                   @variable(model, [1:1], Poly(monomials(MP.x, 0:order)))[1]) for v in vertices(P.graph))
    cons = Dict()
    for v in vertices(P.graph)
        flag = (v in v_target)
        cons[v] = add_stationarity_constraints!(model, MP, v, P, props(P.graph, v)[:cell], w, s + flag*sense)
    end

    for e in edges(P.graph)
        add_coupling_constraints!(model, MP, e, P, w)
    end

    @objective(model, Max, s)
    return model, w
end

"""
    approximate_stationary_measure(MP::MarkovProcess, v::APL, order::Int, solver, P::Partition;
                                   side_infos::BasicSemialgebraicSet)

returns approximate values for the stationary measure on the partition `P`. 
`v` is a polynomial observable whose expectation is minimized when determining the approximation. 
The choice of `v` shall be understood as means to regularize the problem. 
"""
function approximate_stationary_measure(MP::MarkovProcess, v::APL, order::Int, solver, P::Partition,
                                        side_infos = FullSpace(); inner_approx = SOSCone)
    model = SOSModel(solver)
    PolyJuMP.setdefault!(model, PolyJuMP.NonNegPoly, inner_approx)
    @variable(model, s)
    w = Dict(v => (props(P.graph, v)[:cell] isa Singleton ?
                    @variable(model) :
                    @variable(model, [1:1], Poly(monomials(MP.x, 0:order)))[1]) for v in vertices(P.graph))
    ineqs = inequalities(side_infos)
    eqs = equalities(side_infos)
    if !isempty(ineqs)
        @variable(model, μ[ineqs] >= 0)
        ineq_slack = sum(μ[ineq]*(ineq - ineq.a[end]) for ineq in ineqs)
        ineq_obj =  sum(μ[ineq]*ineq.a[end] for ineq in ineqs)
    else
        ineq_slack = 0
        ineq_obj = 0
    end
    if !isempty(eqs)
        @variable(model, λ[eqs])
        eq_slack = sum(λ[eq]*(eq - eq.a[end]) for eq in eqs)
        eq_obj = sum(λ[eq]*eq.a[end] for eq in eqs)
    else
        eq_slack = 0
        eq_obj = 0
    end
    slack = - v + s - eq_slack - ineq_slack 
    cons = Dict()
    for v in vertices(P.graph)
        cons[v] = add_stationarity_constraints!(model, MP, v, P, props(P.graph, v)[:cell], w, slack)
    end

    for e in edges(P.graph)
        add_coupling_constraints!(model, MP, e, P, w)
    end

    @objective(model, Max, s - eq_slack - ineq_slack) 
    optimize!(model)
    dist = []
    for v in vertices(P.graph)
        if props(P.graph, v)[:cell] isa Singleton
            push!(dist, dual(cons[v]))
        elseif props(P.graph, v)[:cell] isa Vector{BasicSemialgebraicSet}
            push!(dist, sum(dual.(cons[v])).a[end])
        elseif props(P.graph, v)[:cell] isa BasicSemialgebraicSet
            push!(dist, dual(cons[v]).a[end])
        end
    end
    return Bound(objective_value(model), model, P, Dict(key => value(w[key]) for key in keys(w))), dist
end

"""
    max_entropy_measure(MP::MarkovProcess, order::Int, solver, P::Partition;
                                   side_infos::BasicSemialgebraicSet)

returns approximate values for the stationary measure which maximizes the entropy on the partition `P`.  
"""
function max_entropy_measure(MP::MarkovProcess, order::Int, solver, P::Partition,
                             side_infos = FullSpace(); inner_approx = SOSCone)
    model = SOSModel(solver)
    PolyJuMP.setdefault!(model, PolyJuMP.NonNegPoly, inner_approx)
    w = Dict(v => (props(P.graph, v)[:cell] isa Singleton ?
                   @variable(model) :
                   @variable(model, [1:1], Poly(monomials(MP.x, 0:order)))[1]) for v in vertices(P.graph))
    @variable(model, u[vertices(P.graph)])
    @variable(model, q[vertices(P.graph)])
    @variable(model, s)
    ineqs = inequalities(side_infos)
    eqs = equalities(side_infos)
    if !isempty(ineqs)
        @variable(model, μ[ineqs] >= 0)
        ineq_slack = sum(μ[ineq]*(ineq - ineq.a[end]) for ineq in ineqs)
        ineq_obj =  sum(μ[ineq]*ineq.a[end] for ineq in ineqs)
    else
        ineq_slack = 0
        ineq_obj = 0
    end
    if !isempty(eqs)
        @variable(model, λ[eqs])
        eq_slack = sum(λ[eq]*(eq - eq.a[end]) for eq in eqs)
        eq_obj = sum(λ[eq]*eq.a[end] for eq in eqs)
    else
        eq_slack = 0
        eq_obj = 0
    end
    cons = Dict()
    for v in vertices(P.graph)
        cons[v] = add_stationarity_constraints!(model, MP, v, P, props(P.graph, v)[:cell], w, s + q[v] - eq_slack - ineq_slack )
    end

    for e in edges(P.graph)
        add_coupling_constraints!(model, MP, e, P, w)
    end

    @constraint(model, [v in vertices(P.graph)], [-1, q[v], u[v]] in MOI.DualExponentialCone())

    @objective(model, Max, -sum(u) + s) 
    optimize!(model)
    dist = []
    for v in vertices(P.graph)
        if props(P.graph, v)[:cell] isa Singleton
            if dual(cons[v]) isa Number 
                push!(dist, dual(cons[v]))
            else
                push!(dist, dual(cons[v]).a[end])
            end
        elseif props(P.graph, v)[:cell] isa Vector{BasicSemialgebraicSet}
            push!(dist, sum(dual.(cons[v])).a[end])
        elseif props(P.graph, v)[:cell] isa BasicSemialgebraicSet
            push!(dist, dual(cons[v]).a[end])
        end
    end
    return Bound(-objective_value(model), model, P, Dict(key => value(w[key]) for key in keys(w))), dist
end