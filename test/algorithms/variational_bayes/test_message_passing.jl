facts("Call step() for VMP algorithm") do
    data = [GaussianDistribution(m=2.0, V=tiny)]
    g = FactorGraph()
    GaussianNode(form=:precision,id=:g_node)
    TerminalNode(id=:t_out)
    TerminalNode(GaussianDistribution(), id=:t_mean)
    TerminalNode(GammaDistribution(), id=:t_prec)
    Edge(n(:g_node).i[:out], n(:t_out), id=:y)
    Edge(n(:t_mean), n(:g_node).i[:mean], id=:m)
    Edge(n(:t_prec), n(:g_node).i[:precision], id=:gam)

    attachReadBuffer(n(:t_out), data)
    mean_out = attachWriteBuffer(n(:g_node).i[:mean].edge)
    prec_out = attachWriteBuffer(n(:g_node).i[:precision].edge)

    algo = VariationalBayes(Dict(
        eg(:y) => GaussianDistribution,
        eg(:m) => GaussianDistribution,
        eg(:gam) => GammaDistribution),
        n_iterations=10)
    prepare!(algo)
    step(algo)

    ForneyLab.ensureParameters!(mean_out[end], (:xi, :W))
    @fact round(mean_out[end].W[1,1], 2) --> 1.79
    @fact round(mean_out[end].xi[1], 2) --> 1.57
    @fact prec_out[end].a --> 1.5
    @fact round(prec_out[end].b, 2) --> 1.91
end

#####################
# Integration tests
#####################

facts("Naive vmp implementation integration tests") do
    context("Gaussian node mean precision batch estimation") do
        # Integration test for the vmp implementation by trying to estimate the mean and precision of a Gaussian

        # Initialize chain
        # Fixed observations drawn from N(5.0, 2.0)
        data = [4.9411489951651735,4.4083330961647595,3.535639074214823,2.1690761263145855,4.740705436131505,5.407175878845115,3.6458623443189957,5.132115496214244,4.485471215629411,5.342809672818667]
        initializeGaussianNodeChain(data)
        n_sections = length(data)

        m_buffer = attachWriteBuffer(n(:m_eq*n_sections).i[2]) # Propagate to the end
        gam_buffer = attachWriteBuffer(n(:gam_eq*n_sections).i[2])

        # Apply mean field factorization
        algo = VariationalBayes(Dict(
            eg(:q_y*(1:n_sections)) => GaussianDistribution,
            eg(:q_m*(1:n_sections)) => GaussianDistribution,
            eg(:q_gam*(1:n_sections)) => GammaDistribution),
            n_iterations=50)

        # Perform vmp updates
        run(algo)

        m_out = m_buffer[end]
        gam_out = gam_buffer[end]

        @fact round(mean(m_out)[1], 3) --> 4.381
        @fact round(var(m_out)[1, 1], 5) --> 0.08313
        @fact round(gam_out.a, 3)  --> 6.000
        @fact round(1/gam_out.b, 4) --> 0.2005 # Scale
    end

    context("Gaussian node mean precision batch estimation for multivariate distributions") do
        # Fixed observations drawn from N(5.0, 2.0)
        data_1 = [4.9411489951651735,4.4083330961647595,3.535639074214823,2.1690761263145855,4.740705436131505,5.407175878845115,3.6458623443189957,5.132115496214244,4.485471215629411,5.342809672818667]
        # Fixed observations drawn from N(2.0, 0.5)
        data_2 = [2.317991577739536,2.8244768760034407,1.2501129068467165,2.5729664094889424,3.05374531248249,1.5149856277603246,2.3119227037528614,2.0264643318813644,1.6248999854457278,0.7425070466631876]
        data = hcat(data_1, data_2)
        
        initializeMvGaussianNodeChain(data)
        n_sections = size(data, 1)

        m_buffer = attachWriteBuffer(n(:m_eq*n_sections).i[2])
        gam_buffer = attachWriteBuffer(n(:gam_eq*n_sections).i[2])

        # Apply mean field factorization
        algo = VariationalBayes(Dict(
            eg(:q_y*(1:n_sections)) => MvGaussianDistribution{2},
            eg(:q_m*(1:n_sections)) => MvGaussianDistribution{2},
            eg(:q_gam*(1:n_sections)) => WishartDistribution{2}),
            n_iterations=50)

        # Perform vmp updates
        run(algo)

        m_out = m_buffer[end]
        gam_out = gam_buffer[end]

        @fact round(mean(m_out), 5) --> [4.38083, 2.02401]
        @fact round(cov(m_out), 5) --> [0.15241 -0.03349; -0.03349 0.08052]
        @fact round(mean(gam_out), 5)  --> [1.03159 0.42907; 0.42907 1.95259]
        @fact round(var(gam_out), 5) --> [0.21283  0.21984; 0.21984 0.76252]
    end

    context("Gaussian node mean precision online estimation") do
        # Integration test for the vmp implementation by trying to estimate the mean and precision of a Gaussian

        # Initialize chain
        # Fixed observations drawn from N(5.0, 2.0)
        data = [4.9411489951651735,4.4083330961647595,3.535639074214823,2.1690761263145855,4.740705436131505,5.407175878845115,3.6458623443189957,5.132115496214244,4.485471215629411,5.342809672818667]
        initializeGaussianNodeChain([1.0]) # Initialize a chain with length 1
        Wrap(n(:mN), n(:m0))
        Wrap(n(:gamN), n(:gam0))

        attachReadBuffer(n(:y1), data)
        m_buffer = attachWriteBuffer(n(:m_eq1).i[2])
        gam_buffer = attachWriteBuffer(n(:gam_eq1).i[2])

        # Apply mean field factorization
        algo = VariationalBayes(Dict(
            eg(:q_y1) => GaussianDistribution,
            eg(:q_m1) => GaussianDistribution,
            eg(:q_gam1) => GammaDistribution),
            n_iterations=50)

        # Perform vmp updates
        run(algo)

        m_out = m_buffer[end]
        gam_out = gam_buffer[end]
        @fact round(mean(m_out)[1], 3) --> 4.941
        @fact round(var(m_out)[1, 1], 3) --> 0.000
        @fact round(gam_out.a, 3) --> 6.000
        @fact round(1/gam_out.b, 4) --> 0.1628 # Scale
    end
end

facts("Structured vmp implementation integration tests") do
    context("Gaussian node joint mean variance estimation") do
        # Initialize chain
        # Samples drawn from N(mean 5.0, prec 0.5): data = randn(100)*(1/sqrt(0.5))+5.0
        data = [4.9411489951651735,4.4083330961647595,3.535639074214823,2.1690761263145855,4.740705436131505,5.407175878845115,3.6458623443189957,5.132115496214244,4.485471215629411,5.342809672818667]
        d_data = [DeltaDistribution(d_k) for d_k in data]
        # d_data = [GaussianDistribution(m=d_k, W=10.0) for d_k in data]
        initializeGaussianNodeChain([0.0]) # Initialize a length 1 chain
        Wrap(n(:mN), n(:m0))
        Wrap(n(:gamN), n(:gam0))

        attachReadBuffer(n(:y1), d_data)
        m_buffer = attachWriteBuffer(n(:m_eq1).i[2])
        gam_buffer = attachWriteBuffer(n(:gam_eq1).i[2])

        # Structured factorization
        algo = VariationalBayes(Dict(
            [eg(:q_m1), eg(:q_gam1)].' => NormalGammaDistribution,
            eg(:q_y1) => GaussianDistribution),
            n_iterations=10)

        run(algo)

        m_out = m_buffer[end]
        gam_out = gam_buffer[end]
        # Reference values from first run
        @fact round(mean(m_out)[1], 3) --> 4.521
        @fact round(var(m_out)[1, 1], 3) --> 0.873 # Uniform gamma priors make the variance collapse
        @fact round(gam_out.a, 3) --> 6.000
        @fact round(1/gam_out.b, 5) --> 0.04549 # Scale
    end
end