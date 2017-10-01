export
ExpectationPropagationRule,
expectationPropagationSchedule,
variationalExpectationPropagationSchedule,
@expectationPropagationRule

abstract ExpectationPropagationRule{factor_type} <: MessageUpdateRule

"""
expectationPropagationSchedule() generates a expectation propagation message passing schedule.
"""
function expectationPropagationSchedule(variables::Vector{Variable})
    ep_sites = collectEPSites(nodes(current_graph))
    breaker_sites = [site.partner for site in ep_sites]
    breaker_types = breakerTypes(breaker_sites)

    schedule = summaryPropagationSchedule(variables; target_sites=[breaker_sites; ep_sites])

    for entry in schedule
        if entry.interface in ep_sites
            entry.msg_update_rule = ExpectationPropagationRule{typeof(entry.interface.node)}
        else
            entry.msg_update_rule = SumProductRule{typeof(entry.interface.node)}
        end
    end

    inferUpdateRules!(schedule, inferred_outbound_types=breaker_types)

    return schedule
end

"""
variationalExpectationPropagationSchedule() generates an expectation propagation message passing schedule
that is limited to the `recognition_factor`. Updates on EP sites are computed with an `ExpectationPropagationRule`,
and updates for external nodes are computed with a `VariationalRule`.
"""
function variationalExpectationPropagationSchedule(recognition_factor::RecognitionFactor)
    internal_edges = recognition_factor.internal_edges
    ep_sites = collectEPSites(nodes(internal_edges))
    breaker_sites = [site.partner for site in ep_sites]
    breaker_types = breakerTypes(breaker_sites)

    # Schedule messages towards recognition distributions and target sites, limited to the internal edges
    schedule = summaryPropagationSchedule(sort(collect(recognition_factor.variables)); target_sites=[breaker_sites; ep_sites], limit_set=internal_edges)

    nodes_connected_to_external_edges = nodesConnectedToExternalEdges(recognition_factor)
    for entry in schedule
        if entry.interface in ep_sites
            entry.msg_update_rule = ExpectationPropagationRule{typeof(entry.interface.node)}
        elseif entry.interface.node in nodes_connected_to_external_edges
            entry.msg_update_rule = VariationalRule{typeof(entry.interface.node)}
        else
            entry.msg_update_rule = SumProductRule{typeof(entry.interface.node)}
        end
    end

    inferUpdateRules!(schedule, inferred_outbound_types=breaker_types)

    return schedule
end

# Because we no longer have access to the interfaces on model construction, we have
# to find the EP sites automatically.
# TODO: this method should be refactored to generalize to other node types
"""
Find default EP sites present in `node_set`
"""
function collectEPSites(node_set::Set{FactorNode})
    ep_sites = Interface[]
    for node in sort(collect(node_set))
        if isa(node, Sigmoid)
            push!(ep_sites, node.i[:real]) # EP site for a Sigmoid node is i[:real]
        end
    end

    return ep_sites
end

# TODO: this method should be refactored to generalize to other node types
"""
Constructs breaker types dictionary for breaker sites
"""
function breakerTypes(breaker_sites::Vector{Interface})
    breaker_types = Dict{Interface, DataType}()
    for site in breaker_sites
        if isa(site.partner.node, Sigmoid)
            breaker_types[site] = Message{Gaussian} # Sigmoid EP site partner requires Gaussian breaker
        end
    end

    return breaker_types
end

expectationPropagationSchedule(variable::Variable) = expectationPropagationSchedule([variable])

function inferUpdateRule!{T<:ExpectationPropagationRule}(   entry::ScheduleEntry,
                                                            rule_type::Type{T},
                                                            inferred_outbound_types::Dict{Interface, DataType})
    # Collect inbound types
    inbound_types = collectInboundTypes(entry, rule_type, inferred_outbound_types)

    # Find outbound id
    outbound_id = findfirst(entry.interface.node.interfaces, entry.interface)    
    
    # Find applicable rule(s)
    applicable_rules = DataType[]
    for rule in leaftypes(entry.msg_update_rule)
        if isApplicable(rule, inbound_types, outbound_id)
            push!(applicable_rules, rule)
        end
    end

    # Select and set applicable rule
    if isempty(applicable_rules)
        error("No applicable msg update rule for $(entry) with outbound id $(outbound_id)")
    elseif length(applicable_rules) > 1
        error("Multiple applicable msg update rules for $(entry) with outbound id $(outbound_id)")
    else
        entry.msg_update_rule = first(applicable_rules)
    end

    return entry
end

function collectInboundTypes{T<:ExpectationPropagationRule}(entry::ScheduleEntry,
                                                            ::Type{T},
                                                            inferred_outbound_types::Dict{Interface, DataType})
    inbound_message_types = DataType[]
    for node_interface in entry.interface.node.interfaces
        push!(inbound_message_types, inferred_outbound_types[node_interface.partner])
    end

    return inbound_message_types
end

"""
@expectationPropagationRule registers a expectation propagation update 
rule by defining the rule type and the corresponding methods for the outboundType 
and isApplicable functions. If no name (type) for the new rule is passed, a 
unique name (type) will be generated. Returns the rule type.
"""
macro expectationPropagationRule(fields...)
    # Init required fields in macro scope
    node_type = :unknown
    outbound_type = :unknown
    inbound_types = :unknown
    outbound_id = :unknown
    name = :auto # Triggers automatic naming unless overwritten

    # Loop over fields because order is unknown
    for arg in fields
        (arg.head == :(=>)) || error("Invalid call to @expectationPropagationRule")

        if arg.args[1].args[1] == :node_type
            node_type = arg.args[2]
        elseif arg.args[1].args[1] == :outbound_type
            outbound_type = arg.args[2]
            (outbound_type.head == :curly && outbound_type.args[1] == :Message) || error("Outbound type for ExpectationPropagationRule should be a Message")
        elseif arg.args[1].args[1] == :inbound_types
            inbound_types = arg.args[2]
            (inbound_types.head == :tuple) || error("Inbound types should be passed as Tuple")
        elseif arg.args[1].args[1] == :outbound_id
            outbound_id = arg.args[2]
        elseif arg.args[1].args[1] == :name
            name = arg.args[2]
        else
            error("Unrecognized field $(arg.args[1].args[1]) in call to @expectationPropagationRule")
        end
    end

    # Assign unique name if not set already
    if name == :auto
        # Added hash ensures that the rule name is unique
        msg_types_hash = string(hash(vcat([outbound_type], inbound_types)))[1:6]
        name = Symbol("EP$(node_type)$(msg_types_hash)")
    end

    # Build validators for isApplicable
    input_type_validators = String[]
    for (i, i_type) in enumerate(inbound_types.args)
        if i_type != :Void
            # Only validate inbounds required for message update
            push!(input_type_validators, "(input_types[$i]==$i_type)")
        end
    end

    expr = parse("""
        begin
            type $name <: ExpectationPropagationRule{$node_type} end
            ForneyLab.outboundType(::Type{$name}) = $outbound_type
            ForneyLab.isApplicable(::Type{$name}, input_types::Vector{DataType}, outbound_id::Int64) = $(join(input_type_validators, " && ")) && (outbound_id == $outbound_id)
            $name
        end
    """)

    return esc(expr)

end