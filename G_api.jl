using Distributed: @everywhere, @distributed, addprocs; addprocs(3)
@everywhere using Distributed: @spawnat
@everywhere include("GSTM_v2.jl")
using Statistics: norm



const hm_vectors   = 4
const vector_size  = 13
const storage_size = 25


const is_layers = [30]
const gs_layers = [35]
const go_layers = [35]


const max_t     = 100
const hm_data   = 20

const lr        = .0005
const hm_epochs = 100



make_model(hm_vectors, vector_size, storage_size, is_layers, gs_layers, go_layers) =
begin
    enc, enc_states = ENCODER(hm_vectors, vector_size, storage_size, is_layers, gs_layers, go_layers)
    dec, dec_states = DECODER(hm_vectors, vector_size, storage_size, is_layers, gs_layers, go_layers)
    model = [enc,dec]
    state = [enc_states,dec_states]
[model, state]
end

(encoder, decoder), (enc_zerostate, dec_zerostate) = make_model(hm_vectors, vector_size, storage_size, is_layers, gs_layers, go_layers)

make_data(hm_data; max_timesteps=50) =
begin
    data = []
    for i in 1:hm_data
        push!(data,
            [
                [[randn(1, vector_size) for iii in 1:hm_vectors] for ii in 1:rand(max_timesteps/2:max_timesteps)],
                [[randn(1, vector_size) for iii in 1:hm_vectors] for ii in 1:rand(max_timesteps/2:max_timesteps)]
            ]
        )
    end
data
end

make_accugrads(hm_vectors, vector_size, storage_size, is_layers, gs_layers, go_layers) =
begin
    accu_grads = []
    for model in [encoder, decoder]
        for mfield in fieldnames(typeof(model))
            net = getfield(model, mfield)
            for nfield in fieldnames(typeof(net))
                layer = getfield(net, nfield)
                for lfield in fieldnames(typeof(layer))
                    field_size = size(getfield(layer, lfield))
                    push!(accu_grads, zeros(field_size))
                end
            end
        end
    end
accu_grads
end


shuffle(arr_in) =
begin
    array_copy = copy(arr_in)
    array_new  = []
    while length(array_copy) > 0
        index = rand(1:length(array_copy))
        e = array_copy[index]
        deleteat!(array_copy, index)
        push!(array_new, e)
    end
array_new
end

accu_grads = make_accugrads(hm_vectors, vector_size, storage_size, is_layers, gs_layers, go_layers)


train(data, (encoder, decoder), enc_zerostate, lr, ep; accu_grads=nothing) =
begin
    @show lr

    losses = []

    for epoch in 1:ep

        print("Epoch ", epoch, ": ")

        loss = 0.0

        # for (g,l) in
        #
        #     (@distributed (vcat) for (x,y) in shuffle(data)
        #
        #         d = @diff sequence_loss(
        #             propogate(encoder, decoder, enc_zerostate, x, length(y)),
        #             y
        #         )
        #
        #         grads(d, encoder, decoder), value(d)
        #
        #     end)
        #
        #     upd!(encoder, decoder, g, lr)
        #     #upd_rms!(encoder, decoder, g, lr, accu_grads, alpha=.9)
        #     loss += sum(l)
        #
        #     for e in g
        #         @show norm(e)
        #     end
        #
        # end

        results =
            @distributed (vcat) for (x,y) in shuffle(data)

                d = @diff sequence_loss(
                        propogate(encoder, decoder, enc_zerostate, x, length(y)),
                        y
                )

                @spawnat 1 print("/")

                grads(d, encoder, decoder), value(d)

            end ; print("\n")

        gs = [zeros(size(e)) for e in results[1][1]]

        for (g,l) in results

            loss += l
            gs   += g

        end

        upd!(encoder, decoder, gs, lr)

        # for (name,g) in zip(names, gs)
        #
        #     # g = trunc(Int, norm(g))
        #     # @show name..., norm(g)
        #     # @info(name, norm(g))
        #c
        # end

        # show_details(encoder, decoder)

        @show loss ; push!(losses, loss)


    end
[encoder, decoder, losses]
end



names = []
for model in [encoder, decoder]
    m = typeof(model)
    for mfield in fieldnames(typeof(model))
        net = getfield(model, mfield)
        for nfield in fieldnames(typeof(net))
            layer = getfield(net, nfield)
            for lfield in fieldnames(typeof(layer))
                push!(names, [m, mfield, nfield, lfield])
            end
        end
    end
end


show_details(enc, dec) =
begin
    for model in [enc, dec]
        m = typeof(model)
        for mfield in fieldnames(typeof(model))
            net = getfield(model, mfield)
            for nfield in fieldnames(typeof(net))
                layer = getfield(net, nfield)
                for lfield in fieldnames(typeof(layer))
                    w_norm = trunc(Int, norm(getfield(layer, lfield)))
                    @info((m, mfield, nfield, lfield), w_norm)
                end
            end
        end
    end
end





@time (enc, dec, loss) =

    train(make_data(hm_data,
           max_timesteps=max_t),
         (encoder, decoder),
          enc_zerostate,
          lr,
          hm_epochs,
          accu_grads=accu_grads)


# using PyPlot: plot
# plot(loss, collect(1:hm_epochs), color="red", linewidth=2.0, linestyle="--")
