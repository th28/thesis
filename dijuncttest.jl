using JuMP
using DisjunctiveProgramming

m = Model()
@variable(m, 0<=x[1:2]<=10)

testcon = @constraint(m, con1[i=1:2], x[i] <= [3,4][i])
@constraint(m, con2[i=1:2], zeros(2)[i] <= x[i])
@constraint(m, con3[i=1:2], [5,4][i] <= x[i])
@constraint(m, con4[i=1:2], x[i] <= [9,6][i])


test=add_disjunction!(m,(con1,con2),(con3,con4), reformulation=:big_m, name = :y)
@proposition(m, y[1] ∨ y[2])

print(m)