using IterativeSolvers
using Base.Test

@testset "Randomized Linear Algebra" begin

srand(1234321)
    
m = n = 100
B = randn(m, n)
nB = norm(B)
p = 1e-5 #Probability of failure

for j = 1 : n
    @test rnorm(B, 2j, p) ≥ nB
    @test rnorms(B, j, p) ≥ nB
end

A = B * B'
k = 1
l, u = reigmin(A, k, p)
@test l ≤ eigmin(A) ≤ u

l, u = reigmax(A, k, p)
@test l ≤ eigmax(A) ≤ u

l, u = rcond(A, k, p)
@test l ≤ cond(A) ≤ u

@test_throws ArgumentError IterativeSolvers.randnn(Char, m)
@test_throws ArgumentError IterativeSolvers.randnn(Char, m, n)
end
