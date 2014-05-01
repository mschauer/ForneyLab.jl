facts("GainEqualityCompositeNode") do
    context("GainEqualityCompositeNode() should initialize a GainEqualityCompositeNode with 3 interfaces") do
        node = GainEqualityCompositeNode()
        @fact typeof(node) => GainEqualityCompositeNode
        @fact length(node.interfaces) => 3
        @fact node.in1 => node.interfaces[1]
        @fact node.out1 => node.interfaces[2]
        @fact node.out2 => node.interfaces[3]
        @fact typeof(node.A) => Array{Float64, 2}
    end

    context("GainEqualityCompositeNode() should define an internal Equality and FixedGain node") do
        node = GainEqualityCompositeNode([5.0])
        @fact typeof(node.equality_node) => EqualityNode
        @fact typeof(node.fixed_gain_node) => FixedGainNode
        @fact node.fixed_gain_node.A => reshape([5.0],1,1)
    end

    context("GainEqualityCompositeNode() should point its own interfaces to the internal node interfaces") do
        node = GainEqualityCompositeNode([1.0])
        @fact node.interfaces[1] => node.equality_node.interfaces[1]
        @fact node.interfaces[2] => node.fixed_gain_node.interfaces[2]
        @fact node.interfaces[3] => node.equality_node.interfaces[3]
    end

    context("A GainEqualityCompositeNode should be able to pass a Gaussian message through its internals") do
        #         _________
        #     in1 |       | out2
        # [N]-----|->[=]--|------>
        #         |   |   |
        #         |   v   |
        #         |  [A]  |
        #         |___|___|
        #             | out1
        #             v 
        #            [N]

        # TODO: this approach needs the graph to be defined, bacause it calls calculateMessage!(). That's not the idea behind the updateNodeMessage! function?

        # Working behaviour
        node = GainEqualityCompositeNode(2.0*eye(2), false) # Flag false to indicate explicit calculations
        c_node1 = ConstantNode(GaussianMessage(W=reshape([1.0, 0.5, 0.5, 1.0], 2, 2), xi=[1.0, 2.0]))
        c_node2 = ConstantNode(GaussianMessage(W=reshape([1.0, 0.5, 0.5, 1.0], 2, 2), xi=[1.0, 2.0]))
        Edge(c_node1.interfaces[1], node.interfaces[1])
        Edge(node.interfaces[2], c_node2.interfaces[1])
        inbound_messages = Array(GaussianMessage, 3)
        #inbound_messages[1] = c_node1.constant
        #inbound_messages[2] = c_node2.constant
        # Forward message
        ForneyLab.updateNodeMessage!(3, node, inbound_messages)
        @fact node.interfaces[3].message.W => reshape([5.0, 2.5, 2.5, 5.0], 2, 2)
        @fact node.interfaces[3].message.xi => [3.0, 6.0]

        #Wanted behaviour
        node = GainEqualityCompositeNode(2.0*eye(2), false) # Flag false to indicate explicit calculations
        inbound_messages = Array(GaussianMessage, 3)
        inbound_messages[1] = GaussianMessage(W=reshape([1.0, 0.5, 0.5, 1.0], 2, 2), xi=[1.0, 2.0])
        inbound_messages[2] = GaussianMessage(W=reshape([1.0, 0.5, 0.5, 1.0], 2, 2), xi=[1.0, 2.0])
        # Forward message
        ForneyLab.updateNodeMessage!(3, node, inbound_messages)
        @fact node.interfaces[3].message.W => reshape([5.0, 2.5, 2.5, 5.0], 2, 2)
        @fact node.interfaces[3].message.xi => [3.0, 6.0]
    end

    context("A GainEqualityCompositeNode should pass a Gaussian message using custom update rules for message passing") do
        # The following tests on the update rules correspond to node 5 from Table 4.1 in:
        # Korl, Sascha. “A Factor Graph Approach to Signal Modelling, System Identification and Filtering.” Hartung-Gorre, 2005.
        node = GainEqualityCompositeNode(2.0*eye(2)) # Defaults flag to true, telling updateNodeMessage! to use the shortcut update rules.
        context("GaussianMessage with (xi,W) parametrization") do
            inbound_messages = Array(GaussianMessage, 3)
            inbound_messages[1] = GaussianMessage(W=reshape([1.0, 0.5, 0.5, 1.0], 2, 2), xi=[1.0, 2.0])
            inbound_messages[2] = GaussianMessage(W=reshape([1.0, 0.5, 0.5, 1.0], 2, 2), xi=[1.0, 2.0])
            # Forward message
            ForneyLab.updateNodeMessage!(3, node, inbound_messages)
            @fact node.interfaces[3].message.W => reshape([5.0, 2.5, 2.5, 5.0], 2, 2)
            @fact node.interfaces[3].message.xi => [3.0, 6.0]
        end
    end
end